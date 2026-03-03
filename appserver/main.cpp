#include "crow.h"
#include "login.cpp"
#include "sqlconn.cpp"

int main()
{
    connectdb();
    crow::SimpleApp app;

    CROW_ROUTE(app, "/login/").methods("POST"_method)([](const crow::request &req)
                                                      { return handle_login(req); });

    app.port(8080).multithreaded().bindaddr("10.5.62.55").run();
}