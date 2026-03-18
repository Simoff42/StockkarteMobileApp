
extern ActiveSessions active_sessions;
extern std::string connectString;

std::string handle_get_user_hives_overview(const crow::request &req)
{
    auto sql = soci::session(soci::mysql, connectString);
    auto body = crow::json::load(req.body);
    std::string session_id = body["sessionId"].s();

    if (!active_sessions.validate_session(session_id))
    {
        crow::json::wvalue response;
        response["status"] = "FAILED";
        return response.dump();
    }

    try
    {
        std::string user_id;
        {
            std::lock_guard<std::mutex> lock(active_sessions.mutex);
            user_id = active_sessions.sessions[session_id].userID;
        }

        crow::json::wvalue response;
        crow::json::wvalue::list hive_list;

        try
        {

            soci::rowset<soci::row> rs = (sql.prepare << "SELECT id, name, place, hivenumber, coworker_table, coordinates FROM masterhives");

            for (soci::rowset<soci::row>::const_iterator it = rs.begin(); it != rs.end(); ++it)
            {
                soci::row const &row = *it;
                int h_id = row.get<int>(0);
                std::string h_name = row.get<std::string>(1, "");
                std::string h_location = row.get<std::string>(2, "");
                std::string h_hivenumber = row.get<std::string>(3, "");
                std::string coworker_table = row.get<std::string>(4, "");
                std::string h_coordinates = row.get<std::string>(5, "");

                if (coworker_table.empty())
                {
                    continue;
                }
                int is_coworker = 0;
                std::string permission;
                std::string check_query = "SELECT COUNT(*), permission FROM " + coworker_table + " WHERE id = :user_id";

                try
                {
                    sql << check_query, soci::into(is_coworker), soci::into(permission), soci::use(user_id);

                    if (is_coworker > 0)
                    {
                        crow::json::wvalue hive_obj;
                        hive_obj["id"] = h_id;
                        hive_obj["name"] = h_name;
                        hive_obj["location"] = h_location;
                        hive_obj["hivenumber"] = h_hivenumber;
                        hive_obj["permission"] = permission;
                        hive_obj["coordinates"] = h_coordinates;

                        hive_list.push_back(std::move(hive_obj));
                    }
                }
                catch (const std::exception &e)
                {
                    std::cerr << "Warning: Could not query table " << coworker_table << " - " << e.what() << std::endl;
                }
            }

            response["status"] = "SUCCESS";
            response["hives"] = std::move(hive_list);
        }
        catch (const std::exception &e)
        {
            response["status"] = "ERROR";
            response["message"] = e.what();
        }

        return response.dump();
    }
    catch (std::exception const &e)
    {
        std::cerr << "Database Query Failed: " << e.what() << '\n';
        crow::json::wvalue error_response;
        error_response["status"] = "FAILED";
        return error_response.dump();
    }
}
