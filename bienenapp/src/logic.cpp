// src/logic.cpp
#include "logic.h"

unsigned val = 0;

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
