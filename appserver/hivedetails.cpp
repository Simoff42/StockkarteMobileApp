extern ActiveSessions active_sessions;
extern std::string connectString;

crow::response handle_get_hive_details(const crow::request &req)
{
    auto sql = soci::session(soci::mysql, connectString);
    auto body = crow::json::load(req.body);
    std::string session_id = body["sessionId"].s();
    int hive_id = body["hiveId"].i();
    std::cout << "Received request for hive details with session ID: " << session_id << " and hive ID: " << hive_id << std::endl;

    if (!active_sessions.validate_session(session_id))
    {
        crow::json::wvalue response;
        response["status"] = "UNAUTHORIZED";
        response["message"] = "Session expired or invalid. Please log in again.";
        return crow::response(401, response.dump());
    }

    std::cout << "Fetching details for hive ID: " << hive_id << std::endl;

    try
    {
        std::string user_id;
        {
            std::lock_guard<std::mutex> lock(active_sessions.mutex);
            user_id = active_sessions.sessions[session_id].userID;
        }

        crow::json::wvalue response;

        // --- SAFE EXTRACTION HELPERS ---
        // These lambdas inspect the underlying database type and safely convert it,
        // preventing std::bad_cast exceptions on Date, Time, and BigInt columns.
        auto extract_string = [](const soci::row &r, std::size_t index) -> std::string
        {
            if (r.get_indicator(index) != soci::i_ok)
                return "";
            switch (r.get_properties(index).get_data_type())
            {
            case soci::dt_string:
                return r.get<std::string>(index);
            case soci::dt_date:
            {
                std::tm t = r.get<std::tm>(index);
                char buf[32];
                strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", &t);
                return std::string(buf);
            }
            case soci::dt_integer:
                return std::to_string(r.get<int>(index));
            case soci::dt_long_long:
                return std::to_string(r.get<long long>(index));
            case soci::dt_unsigned_long_long:
                return std::to_string(r.get<unsigned long long>(index));
            case soci::dt_double:
                return std::to_string(r.get<double>(index));
            default:
                return "";
            }
        };

        auto extract_int = [](const soci::row &r, std::size_t index) -> int
        {
            if (r.get_indicator(index) != soci::i_ok)
                return 0;
            switch (r.get_properties(index).get_data_type())
            {
            case soci::dt_integer:
                return r.get<int>(index);
            case soci::dt_long_long:
                return static_cast<int>(r.get<long long>(index));
            case soci::dt_unsigned_long_long:
                return static_cast<int>(r.get<unsigned long long>(index));
            case soci::dt_double:
                return static_cast<int>(r.get<double>(index));
            case soci::dt_string:
            {
                try
                {
                    return std::stoi(r.get<std::string>(index));
                }
                catch (...)
                {
                    return 0;
                }
            }
            default:
                return 0;
            }
        };
        // -------------------------------

        try
        {
            std::string query = "SELECT id, name, hivenumber, place, street, coordinates, veterinarian, inspector, comment, log_table, volk_table, coworker_table, chem_table, owner, datum, last_mod, active FROM masterhives WHERE id = :hive_id";
            soci::row master_row;
            std::string log_table;
            std::string coworker_table;
            std::string volk_table;
            std::string chem_table;

            sql << query, soci::into(master_row), soci::use(hive_id);

            if (sql.got_data())
            {
                // Extract coworker table first to check permissions
                coworker_table = extract_string(master_row, 11);
                chem_table = extract_string(master_row, 12);

                if (coworker_table.empty())
                {
                    std::cout << "Coworker table name is empty for hive ID: " << hive_id << std::endl;
                    response["status"] = "FAILED";
                    return crow::response(500, response.dump());
                }

                // Authorization Check: Check if user exists in the coworker table
                std::string permission = "none";
                std::string check_query = "SELECT permission FROM " + coworker_table + " WHERE id = :user_id";
                soci::row perm_row;
                sql << check_query, soci::into(perm_row), soci::use(user_id);

                if (!sql.got_data())
                {
                    std::cout << "Access denied: User ID " << user_id << " not found in " << coworker_table << std::endl;
                    response["status"] = "FORBIDDEN";
                    response["message"] = "Access denied. User does not have permission for this hive.";
                    // Return immediately, returning no data
                    return crow::response(403, response.dump());
                }

                // User is authorized, extract their permission level
                permission = extract_string(perm_row, 0);

                // Now populate the response with the hive data
                response["status"] = "SUCCESS";
                response["hive"]["id"] = extract_int(master_row, 0);
                response["hive"]["name"] = extract_string(master_row, 1);
                response["hive"]["hivenumber"] = extract_string(master_row, 2);
                response["hive"]["place"] = extract_string(master_row, 3);
                response["hive"]["street"] = extract_string(master_row, 4);
                response["hive"]["coordinates"] = extract_string(master_row, 5);
                response["hive"]["veterinarian"] = extract_string(master_row, 6);
                response["hive"]["inspector"] = extract_string(master_row, 7);
                response["hive"]["comment"] = extract_string(master_row, 8);

                log_table = extract_string(master_row, 9);
                volk_table = extract_string(master_row, 10);
                // coworker_table is already extracted

                std::string owner_id = extract_string(master_row, 13);
                response["hive"]["owner"] = owner_id;

                // Fetch owner first and last name
                std::string owner_firstname = "Unknown";
                std::string owner_lastname = "Unknown";
                if (!owner_id.empty())
                {
                    try
                    {
                        soci::row owner_row;
                        sql << "SELECT firstname, lastname FROM users WHERE id = :id", soci::into(owner_row), soci::use(owner_id);
                        if (sql.got_data())
                        {
                            owner_firstname = extract_string(owner_row, 0);
                            owner_lastname = extract_string(owner_row, 1);
                        }
                    }
                    catch (const std::exception &e)
                    {
                        std::cout << "Warning: Could not fetch owner name for owner ID " << owner_id << ": " << e.what() << std::endl;
                    }
                }
                response["hive"]["owner_firstname"] = owner_firstname;
                response["hive"]["owner_lastname"] = owner_lastname;

                response["hive"]["datum"] = extract_string(master_row, 14);
                response["hive"]["last_mod"] = extract_string(master_row, 15);
                response["hive"]["active"] = extract_int(master_row, 16);

                response["hive"]["permission"] = permission;

                std::cout << "Hive found and user access granted." << std::endl;

                if (permission == "2") // Admin
                {
                    std::vector<crow::json::wvalue> users_list;
                    std::string users_query = "SELECT u.username, u.firstname, u.lastname, c.permission FROM users u JOIN " + coworker_table + " c ON u.ID = c.id";
                    soci::rowset<soci::row> rs = (sql.prepare << users_query);
                    for (auto it = rs.begin(); it != rs.end(); ++it)
                    {
                        const soci::row &curr_row = *it;
                        crow::json::wvalue user_obj;
                        user_obj["username"] = extract_string(curr_row, 0);
                        user_obj["firstname"] = extract_string(curr_row, 1);
                        user_obj["lastname"] = extract_string(curr_row, 2);
                        user_obj["permission"] = extract_string(curr_row, 3);
                        users_list.push_back(std::move(user_obj));
                    }
                    response["hive"]["users_perm_list"] = std::move(users_list);
                }

                std::vector<crow::json::wvalue> logs_list;
                std::string logs_query = "SELECT id, wetter, temperatur, action, befund, datum, kommentar, last_mod, logid FROM " + log_table + " ORDER BY datum DESC";
                soci::rowset<soci::row> logs_rs = (sql.prepare << logs_query);
                for (auto it = logs_rs.begin(); it != logs_rs.end(); ++it)
                {
                    const soci::row &curr_row = *it;
                    crow::json::wvalue log_obj;
                    log_obj["id"] = extract_int(curr_row, 0);
                    log_obj["wetter"] = extract_string(curr_row, 1);
                    log_obj["temperatur"] = extract_string(curr_row, 2);
                    log_obj["action"] = extract_string(curr_row, 3);
                    log_obj["befund"] = extract_string(curr_row, 4);
                    log_obj["datum"] = extract_string(curr_row, 5);
                    log_obj["kommentar"] = extract_string(curr_row, 6);
                    log_obj["last_mod"] = extract_string(curr_row, 7);
                    log_obj["logid"] = extract_string(curr_row, 8);
                    logs_list.push_back(std::move(log_obj));
                }
                response["hive"]["logs"] = std::move(logs_list);

                std::vector<crow::json::wvalue> volks_list;
                std::string volks_query = "SELECT id, nummer, herkunft, konigin, konigin_jahr, kommentar, active, honigwaben, brutwaben, honigraum, datum, typ FROM " + volk_table;
                soci::rowset<soci::row> volks_rs = (sql.prepare << volks_query);
                for (auto it = volks_rs.begin(); it != volks_rs.end(); ++it)
                {
                    const soci::row &curr_row = *it;
                    crow::json::wvalue volk_obj;
                    volk_obj["id"] = extract_int(curr_row, 0);
                    volk_obj["nummer"] = extract_string(curr_row, 1);
                    volk_obj["herkunft"] = extract_string(curr_row, 2);
                    volk_obj["konigin"] = extract_string(curr_row, 3);
                    volk_obj["konigin_jahr"] = extract_string(curr_row, 4);
                    volk_obj["kommentar"] = extract_string(curr_row, 5);
                    volk_obj["active"] = extract_int(curr_row, 6);
                    volk_obj["honigwaben"] = extract_string(curr_row, 7);
                    volk_obj["brutwaben"] = extract_string(curr_row, 8);
                    volk_obj["honigraum"] = extract_string(curr_row, 9);
                    volk_obj["datum"] = extract_string(curr_row, 10);
                    volk_obj["typ"] = extract_string(curr_row, 11);
                    volks_list.push_back(std::move(volk_obj));
                }
                response["hive"]["volks"] = std::move(volks_list);

                std::vector<crow::json::wvalue> chem_list;
                std::string chem_query = "SELECT id, edatum, expdatum, name, menge, quelle, rdatum, entsorgung, rmenge, active FROM " + chem_table;
                soci::rowset<soci::row> chem_rs = (sql.prepare << chem_query);
                for (auto it = chem_rs.begin(); it != chem_rs.end(); ++it)
                {
                    const soci::row &curr_row = *it;
                    crow::json::wvalue chem_obj;
                    chem_obj["id"] = extract_int(curr_row, 0);
                    chem_obj["edatum"] = extract_string(curr_row, 1);
                    chem_obj["expdatum"] = extract_string(curr_row, 2);
                    chem_obj["name"] = extract_string(curr_row, 3);
                    chem_obj["menge"] = extract_string(curr_row, 4);
                    chem_obj["quelle"] = extract_string(curr_row, 5);
                    chem_obj["rdatum"] = extract_string(curr_row, 6);
                    chem_obj["entsorgung"] = extract_string(curr_row, 7);
                    chem_obj["rmenge"] = extract_string(curr_row, 8);
                    chem_obj["active"] = extract_int(curr_row, 9);
                    chem_list.push_back(std::move(chem_obj));
                }
                response["hive"]["chemicals"] = std::move(chem_list);
            }
            else
            {
                response["status"] = "FAILED";
                response["message"] = "Hive not found.";
                std::cout << "Hive not found with ID: " << hive_id << std::endl;
                return crow::response(404, response.dump());
            }
        }
        catch (const std::exception &e)
        {
            response["status"] = "FAILED";
            std::cout << "Error fetching hive details: " << e.what() << std::endl;
            return crow::response(500, response.dump());
        }
        return crow::response(200, response.dump());
    }
    catch (std::exception const &e)
    {
        std::cout << "Database Query Failed: " << e.what() << '\n';
        crow::json::wvalue response;
        response["status"] = "ERROR";
        response["message"] = e.what();
        return crow::response(500, response.dump());
    }
}