#include <soci/soci.h>
#include <soci/mysql/soci-mysql.h> // The MySQL backend header
#include <iostream>
using namespace soci;

int connectdb()
{
    // 1. Establish Database Connection First
    // Replace 'test' with the name of a database you created in phpMyAdmin
    std::string connectString = "host=127.0.0.1 port=3306 db=test user=root";

    try
    {
        session sql(mysql, connectString);
        std::cout << "Successfully connected to MySQL Database!\n";

        // You can run a quick test query right here if you want!
    }
    catch (std::exception const &e)
    {
        std::cerr << "Database Connection Failed: " << e.what() << '\n';
        return 1; // Exit the program if the DB isn't running
    }

    return 0;
}

int db_handle_login_request()
{
}