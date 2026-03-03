#include "crow.h"
#include "login.cpp"

int main()
{
    // Create a Crow application instance
    crow::SimpleApp app;

    // Define a routing endpoint for the root URL
    CROW_ROUTE(app, "/")(login);

    // Set the port to 8080, enable multithreading, and start the server
    app.port(8080).multithreaded().run();
}