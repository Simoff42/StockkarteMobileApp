#include "crow.h"
#include "login.cpp"
#include "sqlconn.cpp"
#include "overviews.cpp"

ActiveSessions active_sessions;
std::string connectString = "host=127.0.0.1 port=3306 db=test user=root";

int main()
{
    connectdb();
    crow::SimpleApp app;

    CROW_ROUTE(app, "/login/").methods("POST"_method)([](const crow::request &req)
                                                      { return handle_login(req); });

    CROW_ROUTE(app, "/logout/").methods("POST"_method)([](const crow::request &req)
                                                       { return handle_logout(req); });

    CROW_ROUTE(app, "/getUserHivesOverview/").methods("POST"_method)([](const crow::request &req)
                                                                     { return handle_get_user_hives_overview(req); });

    app.port(8080).multithreaded().bindaddr("192.168.1.140").run();
}
