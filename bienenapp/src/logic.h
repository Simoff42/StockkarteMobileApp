#include <stdint.h>
// #include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // Add all the functions you want Flutter to see here!
    int get_value();
    void add_one();
    const char *login(const char *username, const char *password);
    const char *logout();
    const char *get_hives_overview_json();
    const char *get_hive_details_json(int hive_id);

#ifdef __cplusplus
}
#endif