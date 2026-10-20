// Mature SAX input and Writer output own JSON grammar/escaping. The bridge
// owns world Variant rules, bounded callbacks and existing numeric adapters.
#pragma once
#include <rapidjson/writer.h>
#include <boost/json/src.hpp>
#include <boost/json/basic_parser_impl.hpp>
#include <array>
#include <charconv>
#include <cstring>
#include <limits>
