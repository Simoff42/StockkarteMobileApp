#include <string>
#include "crow.h"
#include <soci/soci.h>
#include <soci/mysql/soci-mysql.h> // The MySQL backend header
#include <iostream>
#include <bcrypt.h>
using namespace soci;

std::string handle_login(const crow::request &req)
{
    std::cout << "Received login request with body: " << req.body << std::endl;
    auto body = crow::json::load(req.body);
    std::string username = body["username"].s();
    std::string password = body["password"].s();

    std::string connectString = "host=127.0.0.1 port=3306 db=test user=root";
    try
    {
        session sql(mysql, connectString);

        std::string stored_hash;
        indicator ind;

        // Fetch the hash for the user
        sql << "SELECT password FROM users WHERE username = :username",
            into(stored_hash, ind),
            use(username);

        if (ind != i_ok)
        {
            return "failure";
        }

        stored_hash.erase(stored_hash.find_last_not_of(" \n\r\t") + 1);
        if (stored_hash.length() >= 4 && stored_hash.substr(0, 4) == "$2y$")
        {
            stored_hash[2] = 'a'; // Changes "$2y$" to "$2a$"
        }

        bool is_valid = bcrypt::validatePassword(password, stored_hash);
        if (is_valid)
        {
            std::cout << "User '" << username << "' logged in successfully!" << std::endl;
            return "success";
        }
        else
        {
            std::cout << "Invalid password for user '" << username << "'." << std::endl;
            return "failure";
        }
    }
    catch (std::exception const &e)
    {
        std::cerr << "Database Query Failed: " << e.what() << '\n';
        return "error";
    }
}