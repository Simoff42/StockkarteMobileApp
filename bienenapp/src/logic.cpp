// src/logic.cpp
#include "logic.h"
#include <string>
#include "httplib.h"
#include <iostream>
#include <android/log.h>
#include <nlohmann/json.hpp>
#include <future>
#include <chrono>
#include <regex>
#include <algorithm>

#define LOG_TAG "BienenApp_CPP"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

using json = nlohmann::json;

struct HttpResponse
{
    std::string status;
    std::string body;
};

// GOLBAL VARIABLES

std::string SESSION_ID;
unsigned val = 0;

HttpResponse post_request(const std::string &url, const std::string &body)
{
    LOGI("Preparing to send POST request to %s with body: %s", url.c_str(), body.c_str());

    // Wrap the entire network instantiation and request in an async worker thread
    // We capture 'url' and 'body' by value so the thread has its own safe copies.
    auto async_call = std::async(std::launch::async, [url, body]()
                                 {
        // Instantiate the client inside the thread. 
        // This ensures that if the main thread times out and returns early, 
        // the background thread still safely owns the client memory and won't crash.
        // httplib::Client cli("192.168.1.140", 8080);
        httplib::Client cli("10.5.55.49", 8080);
        
        cli.set_address_family(AF_INET);
        cli.set_keep_alive(false);
        cli.set_connection_timeout(5, 0);
        cli.set_read_timeout(5, 0);
        cli.set_write_timeout(5, 0);
        
        LOGI("HTTP client initialized inside async worker with base URL: http://10.5.48.95 :8080");
        
        // This is the blocking call that might hang infinitely
        return cli.Post(url.c_str(), body, "application/json"); });

    // Enforce a strict 6-second "hard timeout" (1 second longer than your socket timeout)
    auto status = async_call.wait_for(std::chrono::seconds(6));

    if (status == std::future_status::timeout)
    {
        // If we hit this, the OS-level socket completely deadlocked and ignored the httplib timeouts.
        LOGE("CRITICAL: Hard timeout reached! The C++ socket completely locked up.");
        return {"ERROR", "TIMEOUT"};
    }

    // If we get here, the call finished within the 6 seconds. Extract the result.
    auto res = async_call.get();

    LOGI("Sent POST request to %s with body: %s", url.c_str(), body.c_str());
    if (!res)
    {
        LOGE("Request failed with error code: %d", static_cast<int>(res.error()));
        return {"ERROR", "NETWORK_ERROR"};
    }

    LOGI("Received response: %d", res->status);

    switch (res->status)
    {
    case 200:
    case 201:
        return {"SUCCESS", res->body};
    case 400:
        LOGE("Bad request: %s", res->body.c_str());
        return {"ERROR", "BAD_REQUEST"};
    case 401:
        LOGE("Unauthorized");
        return {"ERROR", "UNAUTHORIZED"};
    case 404:
        LOGE("Endpoint not found: %s", url.c_str());
        return {"ERROR", "NOT_FOUND"};
    case 500:
        LOGE("Internal server error");
        return {"ERROR", "INTERNAL_SERVER_ERROR"};
    default:
        LOGE("HTTP error %d: %s", res->status, res->body.c_str());
        return {"ERROR", "HTTP_ERROR"};
    }

    return HttpResponse{"ERROR", "UNKNOWN_ERROR"};
}

json parse_response_body(const std::string &body)
{
    try
    {
        return json::parse(body);
    }
    catch (const json::exception &e)
    {
        LOGE("JSON parse error: %s", e.what());
        return json::object();
    }
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
get_value()
{
    return val;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) void
add_one()
{
    val++;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) const char *
login(const char *username, const char *password)
{
    std::string body = "{\"username\": \"" + std::string(username) + "\", \"password\": \"" + std::string(password) + "\"}";
    HttpResponse response = post_request("/login/", body);
    LOGI("Login response: %s", response.body.c_str());

    if (response.status != "SUCCESS")
    {
        LOGE("Login failed with status: %s", response.body.c_str());
        return strdup(response.body.c_str());
    }
    else
    {
        json response_json = parse_response_body(response.body);
        if (response_json["status"] == "SUCCESS" && response_json.contains("sessionId"))
        {
            SESSION_ID = response_json["sessionId"].get<std::string>();
            LOGI("Login successful! Session ID: %s", SESSION_ID.c_str());
        }
        else
        {
            LOGE("Login failed: %s", response.body.c_str());
        }
        if (response_json.contains("status") && response_json["status"].is_string())
        {
            return strdup(response_json["status"].get<std::string>().c_str());
        }
        else
        {
            return strdup("UNKNOWN");
        }
    }
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) const char *logout()
{
    std::string body = "{\"sessionId\": \"" + SESSION_ID + "\"}";
    HttpResponse response = post_request("/logout/", body);
    LOGI("Logout response: %s", response.body.c_str());
    SESSION_ID = "";

    return strdup(parse_response_body(response.body).value("status", "UNKNOWN").c_str());
}

// Homescreen overview of hives for the logged in user

// Globals
json HIVES_OVERVIEW;

extern "C" __attribute__((visibility("default"))) __attribute__((used)) const char *load_hives_overview()
{
    std::string body = "{\"sessionId\": \"" + SESSION_ID + "\"}";
    HttpResponse response = post_request("/getUserHivesOverview/", body);
    LOGI("Hives overview response: %s", response.body.c_str());

    if (response.status != "SUCCESS")
    {
        LOGE("Failed to load hives overview with status: %s", response.body.c_str());
        return strdup(response.body.c_str());
    }
    else
    {
        // save to a global variable for later use in hive details screen
        HIVES_OVERVIEW = parse_response_body(response.body);

        return strdup(response.status.c_str());
    }
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) const char *get_hives_overview_json()
{
    std::string body = "{\"sessionId\": \"" + SESSION_ID + "\"}";
    HttpResponse response = post_request("/getUserHivesOverview/", body);
    LOGI("Hives overview response: %s", response.body.c_str());

    if (response.status != "SUCCESS")
    {
        LOGE("Failed to load hives overview with status: %s", response.body.c_str());
        return strdup(response.body.c_str());
    }
    else
    {
        // save to a global variable for later use in hive details screen
        HIVES_OVERVIEW = parse_response_body(response.body);
    }
    std::string overview_str = HIVES_OVERVIEW.dump();
    LOGI("Returning hives overview JSON: %s", overview_str.c_str());
    return strdup(overview_str.c_str());
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) const char *get_hive_details_json(int hive_id)
{
    std::string body = "{\"sessionId\": \"" + SESSION_ID + "\", \"hiveId\": " + std::to_string(hive_id) + "}";
    HttpResponse response = post_request("/getHiveDetails/", body);
    LOGI("Hive details response: %s", response.body.c_str());

    if (response.status != "SUCCESS")
    {
        LOGE("Failed to load hive details with status: %s", response.body.c_str());
        return strdup(response.body.c_str());
    }
    else
    {
        return strdup(response.body.c_str());
    }
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) const char *parse_varroa_statistics(const char *logs_json)
{
    try
    {
        json logs = json::parse(logs_json);
        json result = json::array();

        std::regex varroa_regex(R"(([0-9]+)\s*[Vv]arroa.*?([0-9]+)\s*[Tt]ag)");

        for (const auto &log : logs)
        {
            std::string action = log.value("action", "");
            std::string befund = log.value("befund", "");
            std::string datum = log.value("datum", "");

            std::string action_lower = action;
            std::transform(action_lower.begin(), action_lower.end(), action_lower.begin(), ::tolower);

            if (action_lower.find("varroa") != std::string::npos || befund.find("Varroa") != std::string::npos || befund.find("varroa") != std::string::npos)
            {
                std::smatch match;
                if (std::regex_search(befund, match, varroa_regex))
                {
                    if (match.size() >= 3)
                    {
                        double count = std::stod(match[1].str());
                        double days = std::stod(match[2].str());
                        if (days == 0)
                            days = 1; // Prevent division by zero
                        double per_day = count / days;

                        json entry;
                        entry["datum"] = datum;
                        entry["count"] = count;
                        entry["days"] = days;
                        entry["per_day"] = per_day;
                        result.push_back(entry);
                    }
                }
            }
        }

        std::string res_str = result.dump();
        return strdup(res_str.c_str());
    }
    catch (const std::exception &e)
    {
        LOGE("Error parsing varroa stats: %s", e.what());
        return strdup("[]");
    }
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) const char *calculate_comb_history(const char *logs_json, int current_b, int current_h)
{
    try
    {
        json logs = json::parse(logs_json);

        if (!logs.is_array())
        {
            return strdup("[]");
        }

        // Sort logs by date ascending (oldest first)
        std::sort(logs.begin(), logs.end(), [](const json &a, const json &b)
                  {
            std::string dateA = "";
            if (a.contains("datum") && a["datum"].is_string()) dateA = a["datum"].get<std::string>();
            std::string dateB = "";
            if (b.contains("datum") && b["datum"].is_string()) dateB = b["datum"].get<std::string>();
            return dateA < dateB; });

        std::regex brut_regex(R"(([0-9]+)\s*[Bb]rutwaben)");
        std::regex drohnen_regex(R"(([0-9]+)\s*[Dd]rohnenwaben)");
        std::regex honig_regex(R"(([0-9]+)\s*[Hh]onigwaben)");

        // Forward pass for honigraum (Starting from 0 up to current)
        int s_val = 0;
        for (auto &log : logs)
        {
            std::string action = "";
            if (log.contains("action") && log["action"].is_string())
                action = log["action"].get<std::string>();
            std::string befund = "";
            if (log.contains("befund") && log["befund"].is_string())
                befund = log["befund"].get<std::string>();

            std::string action_lower = action;
            std::transform(action_lower.begin(), action_lower.end(), action_lower.begin(), ::tolower);

            int honig_count = 0;
            std::smatch match;
            if (std::regex_search(befund, match, honig_regex) && match.size() >= 2)
            {
                honig_count = std::stoi(match[1].str());
            }

            if (action_lower.find("ausbauen") != std::string::npos)
            {
                s_val += honig_count;
            }
            else if (action_lower.find("reduktion") != std::string::npos)
            {
                s_val -= honig_count;
                if (s_val < 0)
                    s_val = 0;
            }
            else if (action_lower.find("honig ernten") != std::string::npos)
            {
                s_val = 0;
            }

            log["honigraum"] = std::to_string(s_val);
            log["honigwaben"] = std::to_string(current_h); // static
        }

        // Backward pass for brutwaben (Starting from current down to 0)
        int b_val = current_b;
        for (auto it = logs.rbegin(); it != logs.rend(); ++it)
        {
            auto &log = *it;
            log["brutwaben"] = std::to_string(b_val);

            std::string action = "";
            if (log.contains("action") && log["action"].is_string())
                action = log["action"].get<std::string>();
            std::string befund = "";
            if (log.contains("befund") && log["befund"].is_string())
                befund = log["befund"].get<std::string>();

            std::string action_lower = action;
            std::transform(action_lower.begin(), action_lower.end(), action_lower.begin(), ::tolower);

            int brut_count = 0;
            int drohnen_count = 0;
            std::smatch match;

            if (std::regex_search(befund, match, brut_regex) && match.size() >= 2)
            {
                brut_count = std::stoi(match[1].str());
            }
            if (std::regex_search(befund, match, drohnen_regex) && match.size() >= 2)
            {
                drohnen_count = std::stoi(match[1].str());
            }

            if (action_lower.find("ausbauen") != std::string::npos)
            {
                b_val -= (brut_count + drohnen_count);
            }
            else if (action_lower.find("reduktion") != std::string::npos)
            {
                b_val += (brut_count + drohnen_count);
            }
            if (b_val < 0)
                b_val = 0;
        }

        std::string res_str = logs.dump();
        return strdup(res_str.c_str());
    }
    catch (const std::exception &e)
    {
        LOGE("Error calculating comb history: %s", e.what());
        return strdup("[]");
    }
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) const char *submit_action(int hive_id, int volk_id, const char *action, const char *data_json)
{
    try
    {
        json req_body;
        req_body["sessionId"] = SESSION_ID;
        req_body["hiveId"] = hive_id;
        req_body["volkId"] = volk_id;
        req_body["action"] = action;
        req_body["data"] = json::parse(data_json);

        std::string body_str = req_body.dump();
        HttpResponse response = post_request("/addLogEntry/", body_str);
        LOGI("Submit action response: %s", response.body.c_str());

        if (response.status != "SUCCESS")
        {
            LOGE("Failed to submit action with status: %s", response.body.c_str());
        }
        return strdup(response.status.c_str());
    }
    catch (const std::exception &e)
    {
        LOGE("Error in submit_action: %s", e.what());
        return strdup("ERROR");
    }
}