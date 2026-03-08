#include <string>
#include "crow.h"
#include <soci/soci.h>
#include <soci/mysql/soci-mysql.h> // The MySQL backend header
#include <iostream>
#include <bcrypt.h>
using namespace soci;

struct TimedSession
{
    std::string id;
    std::string userID;
    std::chrono::steady_clock::time_point created_at;
    bool is_valid() const
    {
        auto now = std::chrono::steady_clock::now();
        return (now - created_at) < std::chrono::minutes(30); // Session valid for 30 minutes
    }
};

struct ActiveSessions
{
    std::unordered_map<std::string, TimedSession> sessions;
    std::mutex mutex;

    std::string create_session(const std::string &userID)
    {
        thread_local std::mt19937 gen(std::random_device{}());
        std::uniform_int_distribution<> dis(0, 61);
        const char alphanum[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

        std::string session_id;
        session_id.reserve(32);
        for (int i = 0; i < 32; ++i)
        {
            session_id += alphanum[dis(gen)];
        }

        auto now = std::chrono::steady_clock::now();
        std::lock_guard<std::mutex> lock(mutex);
        sessions[session_id] = {session_id, userID, std::chrono::steady_clock::now()};
        return session_id;
    }

    bool validate_session(const std::string &session_id)
    {
        std::lock_guard<std::mutex> lock(mutex);
        auto it = sessions.find(session_id);
        if (it != sessions.end() && it->second.is_valid())
        {
            return true; // Session is valid
        }
        else if (it != sessions.end())
        {
            sessions.erase(it); // Remove expired session
        }
        return false; // Session not found or expired
    }
};

extern ActiveSessions active_sessions;

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
            crow::json::wvalue response;
            response["status"] = "FAILED";
            return response.dump();
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
            int user_id;
            sql << "SELECT ID FROM users WHERE username = :username", into(user_id), use(username);

            crow::json::wvalue response;
            response["status"] = "SUCCESS";
            response["sessionId"] = active_sessions.create_session(std::to_string(user_id));
            return response.dump();
        }
        else
        {
            std::cout << "Invalid password for user '" << username << "'." << std::endl;
            crow::json::wvalue response;
            response["status"] = "FAILED";
            return response.dump();
        }
    }
    catch (std::exception const &e)
    {
        std::cerr << "Database Query Failed: " << e.what() << '\n';
        crow::json::wvalue response;
        response["status"] = "ERROR";
        response["message"] = e.what();
        return response.dump();
    }
}

std::string handle_logout(const crow::request &req)
{
    auto body = crow::json::load(req.body);
    std::string session_id = body["sessionId"].s();

    if (active_sessions.validate_session(session_id))
    {
        active_sessions.sessions.erase(session_id);
        crow::json::wvalue response;
        response["status"] = "SUCCESS";
        return response.dump();
    }
    else
    {
        crow::json::wvalue response;
        response["status"] = "FAILED";
        return response.dump();
    }
}