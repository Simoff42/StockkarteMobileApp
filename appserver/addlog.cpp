#include "crow.h"
#include <soci/soci.h>
#include <string>
#include <cmath>
#include <iostream>
#include <vector>

extern ActiveSessions active_sessions;
extern std::string connectString;

// Helper function to extract strings from crow JSON safely
std::string get_json_string(const crow::json::rvalue &data, const std::string &key)
{
    if (data.has(key))
    {
        if (data[key].t() == crow::json::type::String)
        {
            return data[key].s();
        }
        else if (data[key].t() == crow::json::type::Number)
        {
            double val = data[key].d();
            if (std::floor(val) == val)
            {
                return std::to_string(static_cast<long long>(val));
            }
            else
            {
                return std::to_string(val);
            }
        }
    }
    return "";
}

int get_year(const std::string &color, const std::string &date_str)
{
    int year = 0;
    if (date_str.length() >= 4)
    {
        try
        {
            year = std::stoi(date_str.substr(0, 4));
        }
        catch (...)
        {
        }
    }

    if (color == "unmarkiert" || color == "unmarkierte Königin")
        return year;
    if (color == "kk" || color == "keine Königin gesichtet" || color == "keine Königin")
        return 0;

    int base_year = 0;
    if (color == "weiss" || color == "weisse Königin")
        base_year = 2016;
    else if (color == "gelb" || color == "gelbe Königin")
        base_year = 2017;
    else if (color == "rot" || color == "rote Königin")
        base_year = 2018;
    else if (color == "grün" || color == "gruen" || color == "grüne Königin")
        base_year = 2019;
    else if (color == "blau" || color == "blaue Königin")
        base_year = 2020;
    else
        return year;

    int diff = std::floor((year - base_year) / 5.0);
    return base_year + (diff * 5);
}

crow::response handle_add_log_entry(const crow::request &req)
{
    auto sql = soci::session(soci::mysql, connectString);
    auto body = crow::json::load(req.body);

    std::string session_id = body["sessionId"].s();
    int hive_id = body["hiveId"].i();
    int volk_id = body["volkId"].i();
    std::string action_type = body["action"].s();
    auto data = body["data"];

    if (!active_sessions.validate_session(session_id))
    {
        crow::json::wvalue response;
        response["status"] = "UNAUTHORIZED";
        response["message"] = "Session expired or invalid. Please log in again.";
        return crow::response(401, response.dump());
    }

    std::string user_id;
    {
        std::lock_guard<std::mutex> lock(active_sessions.mutex);
        user_id = active_sessions.sessions[session_id].userID;
    }

    try
    {
        // Fetch tables and verify permissions
        std::string log_table, volk_table, coworker_table;
        std::string query = "SELECT log_table, volk_table, coworker_table FROM masterhives WHERE id = :id";
        soci::row master_row;
        sql << query, soci::into(master_row), soci::use(hive_id);

        if (!sql.got_data())
        {
            crow::json::wvalue res;
            res["status"] = "FAILED";
            res["message"] = "Hive not found.";
            return crow::response(404, res.dump());
        }

        log_table = master_row.get<std::string>(0);
        volk_table = master_row.get<std::string>(1);
        coworker_table = master_row.get<std::string>(2);

        int permission = 0;
        soci::indicator ind;
        sql << "SELECT permission FROM " << coworker_table << " WHERE id = :uid",
            soci::into(permission, ind), soci::use(user_id);

        if (!sql.got_data() || ind != soci::i_ok || permission < 1)
        {
            crow::json::wvalue res;
            res["status"] = "FORBIDDEN";
            res["message"] = "Not enough permissions to add logs.";
            return crow::response(403, res.dump());
        }

        // Global variables for the query
        std::string wetter = get_json_string(data, "wetter");
        std::string temperatur = get_json_string(data, "temperatur");
        std::string kommentar = get_json_string(data, "kommentar");
        if (kommentar.empty())
            kommentar = "-";

        std::string date = get_json_string(data, "datum");
        if (!date.empty() && date.find('T') != std::string::npos)
        {
            date.replace(date.find('T'), 1, " ");
            if (date.find('.') != std::string::npos)
            {
                date = date.substr(0, date.find('.'));
            }
        }

        std::string db_action = "";
        std::string befund = "";
        bool do_insert_log = true;

        // Action Mapping
        if (action_type == "futter")
        {
            db_action = "Füttern";
            befund = get_json_string(data, "menge") + " " + get_json_string(data, "einheit") + " " + get_json_string(data, "typ");
        }
        else if (action_type == "futterE")
        {
            db_action = "Futter entfernen";
            befund = "Futter entfernt";
        }
        else if (action_type == "varroaTn" || action_type == "varroaT")
        {
            db_action = "Varroa behandeln";
            std::string behandlung = get_json_string(data, "behandlung");
            std::string mittel = get_json_string(data, "mittel");
            std::string typ = get_json_string(data, "typ");
            std::string dosierung = get_json_string(data, "dosierung");

            if (mittel.empty())
                mittel = "NULL";
            if (typ.empty())
                typ = "NULL";
            if (dosierung.empty())
                dosierung = "NULL";

            // Generating JSON encoded array just like PHP: [behandlung, mittel, typ, dosierung]
            crow::json::wvalue befund_json;
            befund_json[0] = behandlung;
            befund_json[1] = mittel;
            befund_json[2] = typ;
            befund_json[3] = dosierung;
            befund = befund_json.dump();
        }
        else if (action_type == "varroaTent")
        {
            db_action = "Behandlung entfernen";
            befund = get_json_string(data, "befund");
            if (befund.empty())
                befund = "Varroabehandlung beendet";
        }
        else if (action_type == "varroaC")
        {
            db_action = "Varroa zählen";
            std::string anzahl = get_json_string(data, "anzahl");
            std::string tage = get_json_string(data, "tage");
            if (tage.empty())
                tage = "1";

            std::string periode = (tage == "1") ? "1 Tag" : (tage + " Tagen");
            befund = anzahl + " Varroa in " + periode;
        }
        else if (action_type == "ausbauen")
        {
            db_action = "Ausbauen";
            int bw = std::stoi(get_json_string(data, "brutwaben").empty() ? "0" : get_json_string(data, "brutwaben"));
            int hw = std::stoi(get_json_string(data, "honigwaben").empty() ? "0" : get_json_string(data, "honigwaben"));
            int hr = std::stoi(get_json_string(data, "honigraum").empty() ? "0" : get_json_string(data, "honigraum"));

            std::string befund_parts = "";
            if (bw > 0)
                befund_parts += std::to_string(bw) + " Brutwaben";
            if (hw > 0)
                befund_parts += (befund_parts.empty() ? "" : ", ") + std::to_string(hw) + " Drohnenwaben";
            if (hr > 0)
                befund_parts += (befund_parts.empty() ? "" : ", ") + std::to_string(hr) + " Honigwaben";
            befund = befund_parts + " hinzugefügt";

            sql << "UPDATE " << volk_table << " SET brutwaben = CAST(brutwaben AS SIGNED) + :b, honigwaben = CAST(honigwaben AS SIGNED) + :h, honigraum = CAST(honigraum AS SIGNED) + :r WHERE id = :id",
                soci::use(bw), soci::use(hw), soci::use(hr), soci::use(volk_id);
        }
        else if (action_type == "reduktion")
        {
            db_action = "Reduktion";
            int bw = std::stoi(get_json_string(data, "brutwaben").empty() ? "0" : get_json_string(data, "brutwaben"));
            int hw = std::stoi(get_json_string(data, "honigwaben").empty() ? "0" : get_json_string(data, "honigwaben"));
            int hr = std::stoi(get_json_string(data, "honigraum").empty() ? "0" : get_json_string(data, "honigraum"));

            std::string befund_parts = "";
            if (bw > 0)
                befund_parts += std::to_string(bw) + " Brutwaben";
            if (hw > 0)
                befund_parts += (befund_parts.empty() ? "" : ", ") + std::to_string(hw) + " Drohnenwaben";
            if (hr > 0)
                befund_parts += (befund_parts.empty() ? "" : ", ") + std::to_string(hr) + " Honigwaben";
            befund = befund_parts + " entfernt";

            sql << "UPDATE " << volk_table << " SET brutwaben = GREATEST(0, CAST(brutwaben AS SIGNED) - :b), honigwaben = GREATEST(0, CAST(honigwaben AS SIGNED) - :h), honigraum = GREATEST(0, CAST(honigraum AS SIGNED) - :r) WHERE id = :id",
                soci::use(bw), soci::use(hw), soci::use(hr), soci::use(volk_id);
        }
        else if (action_type == "kontrolle")
        {
            db_action = "Kontrolle";
            std::string q = get_json_string(data, "koenigin");
            std::string brut = get_json_string(data, "brut");
            std::string fut = get_json_string(data, "futter");

            befund = q + ", " + brut + ", Futter " + fut;

            if (q != "keine Königin gesichtet" && q != "kkg")
            {
                int alter = get_year(q, date);
                std::string store_q = (q == "keine Königin" || q == "kk") ? "kk" : q;
                std::string alter_str = std::to_string(alter);
                sql << "UPDATE " << volk_table << " SET konigin = :q, konigin_jahr = :a WHERE id = :id",
                    soci::use(store_q), soci::use(alter_str), soci::use(volk_id);
            }
        }
        else if (action_type == "ernte")
        {
            db_action = "Honig ernten";
            std::string nummer = "";
            sql << "SELECT nummer FROM " << volk_table << " WHERE id = :id", soci::into(nummer), soci::use(volk_id);
            befund = "Honig aus Volk " + nummer;
        }
        else if (action_type == "neueK")
        {
            db_action = "neue Königin";
            std::string farbe = get_json_string(data, "koenigin");
            befund = farbe + "e Königin hinzugefügt";
            int alter = get_year(farbe, date);
            std::string alter_str = std::to_string(alter);
            sql << "UPDATE " << volk_table << " SET konigin = :k, konigin_jahr = :y WHERE id = :id",
                soci::use(farbe), soci::use(alter_str), soci::use(volk_id);
        }
        else if (action_type == "volkV")
        {
            db_action = "Volk vereinigen";
            std::string v2_id_str = get_json_string(data, "vereinigen_mit");
            int v2_id = v2_id_str.empty() ? 0 : std::stoi(v2_id_str);

            std::string num1 = "", num2 = "";
            sql << "SELECT nummer FROM " << volk_table << " WHERE id = :id", soci::into(num1), soci::use(volk_id);
            if (v2_id > 0)
            {
                sql << "SELECT nummer FROM " << volk_table << " WHERE id = :id", soci::into(num2), soci::use(v2_id);
            }

            befund = "Vereinigung von Volk " + num2 + " und " + num1 + " im Kasten " + num1;

            std::string koenigin = get_json_string(data, "koenigin");
            int bw = std::stoi(get_json_string(data, "brutwaben").empty() ? "0" : get_json_string(data, "brutwaben"));
            int hw = std::stoi(get_json_string(data, "honigwaben").empty() ? "0" : get_json_string(data, "honigwaben"));
            int hr = std::stoi(get_json_string(data, "honigraum").empty() ? "0" : get_json_string(data, "honigraum"));
            int alter = get_year(koenigin, date);
            std::string alter_str = std::to_string(alter);

            // Update V1 config
            sql << "UPDATE " << volk_table << " SET konigin = :k, konigin_jahr = :y, brutwaben = :b, honigwaben = :hw, honigraum = :hr WHERE id = :id",
                soci::use(koenigin), soci::use(alter_str), soci::use(bw), soci::use(hw), soci::use(hr), soci::use(volk_id);

            // Disable V2
            if (v2_id > 0)
            {
                sql << "UPDATE " << volk_table << " SET active = 0 WHERE id = :id", soci::use(v2_id);
                // Insert log for V2 too
                sql << "INSERT INTO " << log_table << " (id, wetter, temperatur, action, befund, datum, kommentar, last_mod) "
                    << "VALUES (:id, :w, :t, :a, :b, :d, :k, :m)",
                    soci::use(v2_id), soci::use(wetter), soci::use(temperatur), soci::use(db_action), soci::use(befund),
                    soci::use(date), soci::use(kommentar), soci::use(user_id);
            }
        }
        else if (action_type == "volkA")
        {
            db_action = "Volk auflösen";
            befund = "Grund: " + get_json_string(data, "grund");
            sql << "UPDATE " << volk_table << " SET active = 0 WHERE id = :id", soci::use(volk_id);
        }
        else if (action_type == "volkU")
        {
            db_action = "Volk umziehen";
            std::string neuerK = get_json_string(data, "kasten");
            std::string nummer = "";
            sql << "SELECT nummer FROM " << volk_table << " WHERE id = :id", soci::into(nummer), soci::use(volk_id);

            befund = "Volk von Kasten " + nummer + " in Kasten " + neuerK;
            sql << "UPDATE " << volk_table << " SET nummer = :n WHERE id = :id", soci::use(neuerK), soci::use(volk_id);
        }
        else if (action_type == "det")
        {
            do_insert_log = false;
            std::string herkunft = get_json_string(data, "herkunft");
            sql << "UPDATE " << volk_table << " SET kommentar = :k, herkunft = :h WHERE id = :id",
                soci::use(kommentar), soci::use(herkunft), soci::use(volk_id);
        }
        else if (action_type == "freitext")
        {
            db_action = "Freitext";
            befund = get_json_string(data, "befund");
        }
        else if (action_type == "koniginm")
        {
            db_action = "Königin markiert";
            std::string q = get_json_string(data, "koenigin");
            befund = "Königin " + q + " markiert";
            sql << "UPDATE " << volk_table << " SET konigin = :q WHERE id = :id", soci::use(q), soci::use(volk_id);
        }
        else if (action_type == "schwarmE")
        {
            db_action = "Schwarm einlogiert";
            std::string nummer = get_json_string(data, "nummer");
            befund = "Schwarm in Kasten " + nummer + " einlogiert";

            std::string q = get_json_string(data, "koenigin");
            std::string herkunft = get_json_string(data, "herkunft");
            std::string bw = get_json_string(data, "brutwaben");
            std::string hw = get_json_string(data, "honigwaben");
            std::string hr = get_json_string(data, "honigraum");

            sql << "UPDATE " << volk_table << " SET nummer = :n, konigin = :q, kommentar = :k, herkunft = :hk, honigwaben = :hw, brutwaben = :bw, honigraum = :hr WHERE id = :id",
                soci::use(nummer), soci::use(q), soci::use(kommentar), soci::use(herkunft), soci::use(hw), soci::use(bw), soci::use(hr), soci::use(volk_id);
        }
        else
        {
            // Fallback generic handler
            db_action = action_type;
            befund = get_json_string(data, "befund");
        }

        // Execute log insertion
        if (do_insert_log)
        {
            sql << "INSERT INTO " << log_table << " (id, wetter, temperatur, action, befund, datum, kommentar, last_mod) "
                << "VALUES (:id, :w, :t, :a, :b, :d, :k, :m)",
                soci::use(volk_id), soci::use(wetter), soci::use(temperatur), soci::use(db_action), soci::use(befund),
                soci::use(date), soci::use(kommentar), soci::use(user_id);
        }

        // Update Masterhive modified tag
        sql << "UPDATE masterhives SET last_mod = :m WHERE id = :h", soci::use(user_id), soci::use(hive_id);

        crow::json::wvalue res;
        res["status"] = "SUCCESS";
        return crow::response(200, res.dump());
    }
    catch (std::exception const &e)
    {
        std::cerr << "AddLogEntry Exception: " << e.what() << std::endl;
        crow::json::wvalue res;
        res["status"] = "ERROR";
        res["message"] = e.what();
        return crow::response(500, res.dump());
    }
}