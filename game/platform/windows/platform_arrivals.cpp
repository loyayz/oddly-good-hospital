// Exact arithmetic and LP backend. Hospital facts and random state never enter here.
#include "gdextension_interface.h"
#include "platform_guard_abi.h"
#include "soplex.h"
#include "scip/scip.h"
#include "scip/scipdefplugins.h"
#include "scip/scip_exact.h"
#include "scip/cons_exactlinear.h"
#include "scip/rational.h"
#include "scip/rationalgmp.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <boost/geometry.hpp>
#include <boost/graph/adjacency_list.hpp>
#include <boost/graph/max_cardinality_matching.hpp>
#include <boost/graph/connected_components.hpp>
#include <boost/graph/dijkstra_shortest_paths.hpp>
#include <boost/graph/depth_first_search.hpp>
#include <boost/iterator/transform_iterator.hpp>
#include "platform_graph_reachability.h"
#include <queue>
#include "platform_json_stream.h"
#include <boost/geometry/index/rtree.hpp>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <iterator>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <stdexcept>
#include <string>
#include <tuple>
#include <vector>

extern "C" uint64_t ogh_current_thread_cpu_us(void);
extern "C" int ogh_monotonic_clock(int64_t* ticks, int64_t* frequency);

namespace {
using Q = soplex::Rational;
using Z = soplex::Integer;
// SCIP 10.1 RECTLU uses process-global GMP scratch, initialized/freed by
// each transformed factorization. Original problems may persist; transformed
// solves must neither overlap nor outlive the native call that owns them.
std::recursive_mutex discrete_mutex;
int64_t micros() { return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count(); }
struct Timer {
    std::map<std::string, int64_t>& values; const char* name; int64_t started = micros();
    Timer(std::map<std::string, int64_t>& target, const char* key) : values(target), name(key) {}
    ~Timer() { values[name] += micros() - started; }
};
struct V;
V timing_values(const std::map<std::string, int64_t>& values);
struct Raw { alignas(8) unsigned char data[OGH_VARIANT_SIZE]; };
struct Builtin { alignas(8) unsigned char data[8]; };
GDExtensionInterfaceVariantNewNil new_nil;
GDExtensionInterfaceVariantNewCopy new_copy;
GDExtensionInterfaceVariantDestroy destroy;
GDExtensionInterfaceVariantGetType type;
GDExtensionInterfaceStringNewWithUtf8Chars new_string;
GDExtensionInterfaceStringToUtf8Chars to_utf8;
GDExtensionInterfaceStringNameNewWithUtf8Chars new_name;
GDExtensionInterfaceDictionaryOperatorIndex dict_index;
GDExtensionInterfaceArrayOperatorIndexConst array_index;
GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class;
GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
GDExtensionVariantFromTypeConstructorFunc from_type[GDEXTENSION_VARIANT_TYPE_VARIANT_MAX];
GDExtensionTypeFromVariantConstructorFunc to_type[GDEXTENSION_VARIANT_TYPE_VARIANT_MAX];
GDExtensionPtrConstructor construct[GDEXTENSION_VARIANT_TYPE_VARIANT_MAX];
GDExtensionPtrDestructor destruct[GDEXTENSION_VARIANT_TYPE_VARIANT_MAX];
GDExtensionPtrBuiltInMethod array_size, array_append, dictionary_keys, dictionary_get;
GDExtensionClassLibraryPtr library;
Builtin math_class;
Builtin model_class, ref_class;
GDExtensionInterfaceClassdbConstructObject3 construct_object;
GDExtensionInterfaceObjectSetInstance set_instance;
GDExtensionInterfaceObjectMethodBindPtrcall object_ptrcall;
GDExtensionMethodBindPtr notification;

struct V {
    Raw raw;
    V() { new_nil(&raw); }
    explicit V(GDExtensionConstVariantPtr source) { new_copy(&raw, source); }
    V(const V& other) { new_copy(&raw, &other.raw); }
    V& operator=(const V& other) {
        if (this != &other) { destroy(&raw); new_copy(&raw, &other.raw); }
        return *this;
    }
    ~V() { destroy(&raw); }
    static V typed(GDExtensionVariantType kind, const void* source) {
        V result; destroy(&result.raw); from_type[kind](&result.raw, const_cast<void*>(source)); return result;
    }
    static V text(const std::string& value) {
        Builtin string; new_string(&string, value.c_str());
        V result = typed(GDEXTENSION_VARIANT_TYPE_STRING, &string);
        destruct[GDEXTENSION_VARIANT_TYPE_STRING](&string); return result;
    }
    static V number(int64_t value) { return typed(GDEXTENSION_VARIANT_TYPE_INT, &value); }
    bool nil() const { return type(&raw) == GDEXTENSION_VARIANT_TYPE_NIL; }
    std::string text() const {
        Builtin string; to_type[GDEXTENSION_VARIANT_TYPE_STRING](&string, const_cast<Raw*>(&raw));
        int64_t length = to_utf8(&string, nullptr, 0);
        std::string result(static_cast<size_t>(length), '\0');
        to_utf8(&string, &result[0], length);
        destruct[GDEXTENSION_VARIANT_TYPE_STRING](&string); return result;
    }
    int64_t number() const { int64_t value; to_type[GDEXTENSION_VARIANT_TYPE_INT](&value, const_cast<Raw*>(&raw)); return value; }
};
template<GDExtensionVariantType Kind> struct B {
    Builtin raw;
    B() { construct[Kind](&raw, nullptr); }
    explicit B(const V& source) { to_type[Kind](&raw, const_cast<Raw*>(&source.raw)); }
    B(const B&) = delete;
    ~B() { destruct[Kind](&raw); }
    V value() const { return V::typed(Kind, &raw); }
};
struct A : B<GDEXTENSION_VARIANT_TYPE_ARRAY> {
    using B::B;
    int64_t size() const { int64_t size; array_size(const_cast<Builtin*>(&raw), nullptr, &size, 0); return size; }
    V at(int64_t index) const { return V(array_index(&raw, index)); }
    void append(const V& value) { const void* args[] = { &value.raw }; array_append(&raw, args, nullptr, 1); }
};
struct D : B<GDEXTENSION_VARIANT_TYPE_DICTIONARY> {
    using B::B;
    V get(const char* key) const {
        return get(V::text(key));
    }
    V get(const V& key) const {
        V result, fallback;
        const void* args[] = {&key.raw, &fallback.raw};
        dictionary_get(const_cast<Builtin*>(&raw), args, &result.raw, 2);
        return result;
    }
    void set(const char* key, const V& value) {
        V name = V::text(key); auto slot = dict_index(&raw, &name.raw);
        destroy(slot); new_copy(slot, &value.raw);
    }
    V keys() const { A keys; dictionary_keys(const_cast<Builtin*>(&raw), nullptr, &keys.raw, 0); return keys.value(); }
};

std::string rational_input(const V& value) {
    if (type(&value.raw) == GDEXTENSION_VARIANT_TYPE_INT) return std::to_string(value.number());
    if (type(&value.raw) != GDEXTENSION_VARIANT_TYPE_DICTIONARY) throw std::runtime_error("精确分数必须是整数或分数字典");
    D fraction(value); V numerator = fraction.get("n"), denominator = fraction.get("d");
    if (type(&numerator.raw) != GDEXTENSION_VARIANT_TYPE_STRING || type(&denominator.raw) != GDEXTENSION_VARIANT_TYPE_STRING)
        throw std::runtime_error("精确分数需要十进制文本");
    std::string n = numerator.text(), d = denominator.text();
    auto decimal = [](const std::string& text) {
        size_t first = !text.empty() && (text[0] == '-' || text[0] == '+') ? 1 : 0;
        return first < text.size() && std::all_of(text.begin() + first, text.end(), [](char digit) { return digit >= '0' && digit <= '9'; });
    };
    if (!decimal(n) || !decimal(d)) throw std::runtime_error("精确分数不是十进制整数");
    if (d.find_first_not_of("+-0") == std::string::npos) throw std::runtime_error("精确分数分母不能为零");
    return n + "/" + d;
}
Q rational(const V& value) {
    Q result(rational_input(value).c_str());
    // GMP's string assignment does not reduce fractions. Arithmetic assumes
    // canonical operands, and the saved decimal protocol requires them too.
    mpq_canonicalize(result.backend().data());
    return result;
}
V fraction(const Q& value) {
    D result;
    result.set("n", V::text(numerator(value).str()));
    result.set("d", V::text(denominator(value).str()));
    return result.value();
}
V timing_values(const std::map<std::string, int64_t>& values) {
    D result; for (const auto& value : values) result.set(value.first.c_str(), V::number(value.second)); return result.value();
}
V failure(const std::string& reason) {
    D result;
    result.set("error", V::text("invalid_resource_model"));
    result.set("bottleneck", V::text(reason));
    return result.value();
}
V empty() {
    D result; A assignments;
    result.set("capacity", fraction(0)); result.set("assignments", assignments.value());
    result.set("bottleneck", V::text("缺少完整可接诊资源束")); return result.value();
}

using Resources = std::map<int, Q>;
struct Node { bool choice; Resources resources; std::vector<int> children; };
struct Member { int index; Q probability; };
struct Case { int root; Q probability; std::vector<Member> members; };
struct Column { int case_index; Resources resources; };

void scip_check(SCIP_RETCODE result) {
    if (result != SCIP_OKAY) throw std::runtime_error("SCIP 精确结构求解失败: " + std::to_string(result));
}
struct Exact {
    SCIP_RATIONAL* value = nullptr;
    explicit Exact(const Q& source = 0) {
        scip_check(SCIPrationalCreate(&value));
        SCIPrationalSetGMP(value, source.backend().data());
    }
    Exact(const Exact&) = delete;
    ~Exact() { SCIPrationalFree(&value); }
};
struct PackingProgram {
    SCIP* scip = nullptr;
    std::vector<SCIP_VAR*> variables;
    std::vector<Q> bounds;
    std::vector<bool> integral;
    std::vector<bool> objectives;
    struct Row { std::vector<std::pair<int, Q>> terms; Q upper; bool equality; SCIP_CONS* constraint; };
    std::vector<Row> rows;
    int64_t exact_polishes = 0;
    mutable std::map<std::string, int64_t> timing;
    std::vector<soplex::DSVectorRational> polish_columns;
    PackingProgram() {
        try {
            scip_check(SCIPcreate(&scip));
            scip_check(SCIPenableExactSolving(scip, TRUE));
            if (!SCIPisExact(scip)) throw std::runtime_error("SCIP 未启用精确求解");
            scip_check(SCIPincludeDefaultPlugins(scip));
            scip_check(SCIPsetCharParam(scip, "exact/safedbmethod", 'e'));
            SCIPsetMessagehdlrQuiet(scip, TRUE);
            scip_check(SCIPcreateProbBasic(scip, "hospital_structure"));
            scip_check(SCIPsetObjsense(scip, SCIP_OBJSENSE_MAXIMIZE));
        } catch (...) { if (scip) SCIPfree(&scip); throw; }
    }
    ~PackingProgram() {
        for (auto*& variable : variables) SCIPreleaseVar(scip, &variable);
        SCIPfree(&scip);
    }
    int variable(const Q& upper, SCIP_VARTYPE kind, bool objective = false) {
        SCIP_VAR* variable = nullptr;
        scip_check(SCIPcreateVarBasic(scip, &variable, ("v" + std::to_string(variables.size())).c_str(), 0, mpq_get_d(upper.backend().data()), objective ? 1 : 0, kind));
        variables.push_back(variable);
        bounds.push_back(upper);
        integral.push_back(kind != SCIP_VARTYPE_CONTINUOUS);
        objectives.push_back(objective);
        Exact lower, higher(upper);
        scip_check(SCIPaddVarExactData(scip, variable, lower.value, higher.value, nullptr));
        scip_check(SCIPaddVar(scip, variable));
        return static_cast<int>(variables.size()) - 1;
    }
    int integer(int upper, bool objective = false) { return variable(upper, upper == 1 ? SCIP_VARTYPE_BINARY : SCIP_VARTYPE_INTEGER, objective); }
    int continuous(const Q& upper, bool objective = false) { return variable(upper, SCIP_VARTYPE_CONTINUOUS, objective); }
    int binary(bool objective = false) { return integer(1, objective); }
    void equal(std::vector<std::pair<int, int>> terms) {
        std::vector<std::pair<int, Q>> exact;
        for (const auto& term : terms) exact.emplace_back(term.first, Q(term.second));
        equal_rational(std::move(exact));
    }
    void at_most(std::vector<std::pair<int, int>> terms, int upper) {
        std::vector<std::pair<int, Q>> exact;
        for (const auto& term : terms) exact.emplace_back(term.first, Q(term.second));
        less_equal(std::move(exact), Q(upper));
    }
    void equal_rational(std::vector<std::pair<int, Q>> terms) {
        less_equal(std::move(terms), Q(0), true);
    }
    int less_equal(std::vector<std::pair<int, Q>> terms, const Q& upper, bool equality = false) {
        std::map<int, Q> compact;
        for (const auto& term : terms) compact[term.first] += term.second;
        terms.clear();
        for (const auto& term : compact) if (term.second != 0) terms.push_back(term);
        std::vector<SCIP_VAR*> vars;
        std::vector<SCIP_RATIONAL*> coefficients;
        std::vector<std::unique_ptr<Exact>> owned;
        for (const auto& term : terms) {
            vars.push_back(variables.at(term.first));
            owned.emplace_back(new Exact(term.second)); coefficients.push_back(owned.back()->value);
        }
        Exact lower(upper), higher(upper);
        if (!equality) SCIPrationalSetNegInfinity(lower.value);
        SCIP_CONS* constraint = nullptr;
        scip_check(SCIPcreateConsBasicExactLinear(scip, &constraint, ("r" + std::to_string(rows.size())).c_str(), static_cast<int>(vars.size()), vars.data(), coefficients.data(), lower.value, higher.value));
        auto status = SCIPaddCons(scip, constraint);
        auto* original = constraint; // The original problem retains this constraint.
        SCIPreleaseCons(scip, &constraint); scip_check(status);
        rows.push_back({std::move(terms), upper, equality, original});
        return static_cast<int>(rows.size()) - 1;
    }
    void reopen() { scip_check(SCIPfreeTransform(scip)); }
    void change_bound(int variable, const Q& upper) {
        if (bounds.at(variable) == upper) return;
        Exact value(upper);
        scip_check(SCIPchgVarUbExact(scip, variables.at(variable), value.value));
        bounds.at(variable) = upper;
    }
    void change_upper(int row, const Q& upper) {
        if (rows.at(row).upper == upper) return;
        Exact value(upper);
        scip_check(SCIPchgRhsExactLinear(scip, rows.at(row).constraint, value.value));
        rows.at(row).upper = upper;
    }
    void change_coefficient(int row, int variable, const Q& coefficient) {
        polish_columns.clear();
        Exact value(coefficient);
        scip_check(SCIPchgCoefExactLinear(scip, rows.at(row).constraint, variables.at(variable), value.value));
        auto& terms = rows.at(row).terms;
        for (auto& term : terms) if (term.first == variable) { term.second = coefficient; return; }
        terms.emplace_back(variable, coefficient);
    }
    std::vector<Q> polish_fixed(const std::vector<Q>& incumbent) {
        Timer whole(timing, "fixed_lp_total_us");
        int64_t started = micros();
        using namespace soplex;
        // SCIP's search has already released its transformed factorization.
        // Fix only the integral choices and optimize continuous flows exactly.
        SoPlex lp;
        lp.setIntParam(SoPlex::VERBOSITY, 0);
        lp.setIntParam(SoPlex::OBJSENSE, SoPlex::OBJSENSE_MAXIMIZE);
        lp.setIntParam(SoPlex::SYNCMODE, SoPlex::SYNCMODE_AUTO);
        lp.setIntParam(SoPlex::SOLVEMODE, SoPlex::SOLVEMODE_RATIONAL);
        lp.setIntParam(SoPlex::CHECKMODE, SoPlex::CHECKMODE_RATIONAL);
        lp.setRealParam(SoPlex::FEASTOL, 0.0); lp.setRealParam(SoPlex::OPTTOL, 0.0);
        if (polish_columns.empty()) {
            polish_columns.resize(variables.size());
            for (size_t i = 0; i < rows.size(); ++i)
                for (const auto& term : rows[i].terms) polish_columns[term.first].add(static_cast<int>(i), term.second);
        }
        for (size_t i = 0; i < rows.size(); ++i) {
            const Row& row = rows[i];
            lp.addRowRational(LPRowRational(row.equality ? row.upper : Q(-infinity), DSVectorRational(), row.upper));
        }
        for (size_t i = 0; i < variables.size(); ++i)
            lp.addColRational(LPColRational(objectives[i] ? 1 : 0, polish_columns[i], integral[i] ? incumbent[i] : bounds[i], integral[i] ? incumbent[i] : Q(0)));
        timing["fixed_lp_assembly_us"] += micros() - started;
        started = micros();
        ++exact_polishes;
        if (lp.optimize() != SPxSolver::OPTIMAL) throw std::runtime_error("离散配置未取得精确可行流");
        timing["fixed_lp_solve_us"] += micros() - started;
        VectorRational primal(static_cast<int>(variables.size()));
        if (!lp.getPrimalRational(primal)) throw std::runtime_error("离散配置缺少精确原始解");
        std::vector<Q> result;
        for (size_t i = 0; i < variables.size(); ++i) result.push_back(primal[static_cast<int>(i)]);
        return result;
    }
    bool valid_values(const std::vector<Q>& values) const {
        Timer timer(timing, "original_validation_us");
        if (values.size() != variables.size()) return false;
        for (size_t i = 0; i < values.size(); ++i)
            if (values[i] < 0 || values[i] > bounds[i] || (integral[i] && mpz_cmp_ui(mpq_denref(values[i].backend().data()), 1) != 0)) return false;
        for (const auto& row : rows) {
            Q total = 0;
            for (const auto& term : row.terms) total += term.second * values[term.first];
            if (total > row.upper || (row.equality && total < row.upper)) return false;
        }
        return true;
    }
    std::vector<Q> solve_rational() {
        Timer timer(timing, "discrete_total_us");
        struct TransformScope {
            SCIP* problem;
            ~TransformScope() { if (problem) SCIPfreeTransform(problem); }
            void release() { scip_check(SCIPfreeTransform(problem)); problem = nullptr; }
        } transform{scip};
        int64_t search_started = micros();
        scip_check(SCIPsolve(scip));
        timing["scip_search_us"] += micros() - search_started;
        if (SCIPgetStatus(scip) != SCIP_STATUS_OPTIMAL || !SCIPisExact(scip)) throw std::runtime_error("结构规模尚未得到精确最优解");
        SCIP_SOL* solution = SCIPgetBestSol(scip);
        if (!solution) throw std::runtime_error("结构规模缺少完整解");
        std::vector<Q> values;
        Exact value;
        for (size_t i = 0; i < variables.size(); ++i) {
            SCIPgetSolValExact(scip, solution, variables[i], value.value);
            auto* q = SCIPrationalGetGMP(value.value);
            Q number; mpq_set(number.backend().data(), *q);
            if ((integral[i] && mpz_cmp_ui(mpq_denref(*q), 1) != 0) || number < 0 || number > bounds[i])
                throw std::runtime_error("精确离散求解违反变量范围或整数约束");
            values.push_back(std::move(number));
        }
        Q objective = 0;
        for (size_t i = 0; i < values.size(); ++i) if (objectives[i]) objective += values[i];
        Exact dual;
        SCIPgetDualboundExact(scip, dual.value);
        Q bound; mpq_set(bound.backend().data(), *SCIPrationalGetGMP(dual.value));
        transform.release();
        if (objective != bound) values = polish_fixed(values);
        objective = 0;
        for (size_t i = 0; i < values.size(); ++i) {
            const Q& number = values[i];
            if (number < 0 || number > bounds[i] || (integral[i] && mpz_cmp_ui(mpq_denref(number.backend().data()), 1) != 0)) throw std::runtime_error("精确离散求解违反变量范围或整数约束");
            if (objectives[i]) objective += number;
        }
        if (!valid_values(values)) throw std::runtime_error("结构配置违反原始资源约束");
        if (objective != bound) throw std::runtime_error("精确目标与证明界不一致: " + objective.str() + " != " + bound.str());
        return values;
    }
    std::vector<int> solve() {
        auto exact = solve_rational(); std::vector<int> values;
        for (const Q& value : exact) values.push_back(static_cast<int>(mpz_get_si(mpq_numref(value.backend().data()))));
        return values;
    }
};

std::string optional_text(const D& source, const char* key) {
    V value = source.get(key); return value.nil() ? "" : value.text();
}
std::vector<std::string> structural_resources(const D& source) {
    std::vector<std::string> result;
    V raw = source.get("structural_resources");
    if (!raw.nil()) {
        A resources(raw);
        for (int64_t i = 0; i < resources.size(); ++i) result.push_back(resources.at(i).text());
    }
    std::sort(result.begin(), result.end()); result.erase(std::unique(result.begin(), result.end()), result.end());
    return result;
}
using Pattern = std::tuple<std::vector<std::string>, std::string, std::string>;
std::set<std::string> dictionary_names(const D& source) {
    std::set<std::string> result; A keys(source.keys());
    for (int64_t i = 0; i < keys.size(); ++i) result.insert(keys.at(i).text());
    return result;
}
// Exact small-set encoding; a bound selects the implicit encoding without
// dropping any candidate or retaining a partial expansion.
struct StructureExpansionLimit {};
V structure_flat(const V& raw_cases, const V& raw_blocked, const V& raw_reception, int64_t bed_limit) {
    if (bed_limit < 1 || bed_limit > INT32_MAX) throw std::runtime_error("无效的病房覆盖上限");
    D blocked(raw_blocked), reception(raw_reception);
    D people(reception.get("people")), desks(reception.get("desks"));
    const auto blocked_ids = dictionary_names(blocked), people_ids = dictionary_names(people), desk_ids = dictionary_names(desks);
    int64_t ratio = reception.get("ratio").number();
    if (ratio < 1 || ratio > INT32_MAX) throw std::runtime_error("无效的接待结构比例");
    auto available = [&](const std::string& resource) { return !blocked_ids.count(resource); };
    using Options = std::set<std::vector<std::string>>;
    std::map<Pattern, Options> terminals;
    std::map<Options, int> factor_ids;
    std::vector<Options> factors;
    std::map<std::vector<int>, Options> combinations;
    std::set<std::pair<Pattern, std::vector<int>>> processed;
    std::set<std::pair<std::string, std::string>> reception_edges;
    auto reception_part = [&](const D& part) {
        V raw = part.get("resources"); if (raw.nil()) return;
        D resources(raw); A keys(resources.keys());
        std::vector<std::string> local_people, local_desks;
        for (int64_t i = 0; i < keys.size(); ++i) {
            V key = keys.at(i); std::string name = key.text();
            if (!available(name)) continue;
            if (people_ids.count(name)) local_people.push_back(name);
            if (desk_ids.count(name)) local_desks.push_back(name);
        }
        for (const auto& person : local_people) for (const auto& desk : local_desks) reception_edges.emplace(person, desk);
    };
    A cases(raw_cases);
    for (int64_t i = 0; i < cases.size(); ++i) {
        D current(cases.at(i)); A bases(current.get("bundles"));
        V raw_groups = current.get("choice_groups");
        D groups = raw_groups.nil() ? D() : D(raw_groups);
        V reception_bundles = current.get("reception_bundles");
        if (!reception_bundles.nil()) {
            A parts(reception_bundles);
            for (int64_t j = 0; j < parts.size(); ++j) reception_part(D(parts.at(j)));
        }
        std::map<std::string, int> prefixes;
        std::map<std::string, Options> expanded;
        std::set<std::string> expansion_visiting;
        std::function<Options(const D&)> expand_part;
        std::function<const Options&(const std::string&)> expand_group;
        expand_group = [&](const std::string& name) -> const Options& {
            auto found = expanded.find(name); if (found != expanded.end()) return found->second;
            if (!expansion_visiting.insert(name).second) throw std::runtime_error("结构选择依赖存在循环");
            V raw = groups.get(V::text(name)); if (raw.nil()) throw std::runtime_error("结构配置缺少初诊选项");
            A options(raw); Options values;
            for (int64_t k = 0; k < options.size(); ++k) {
                auto next = expand_part(D(options.at(k))); values.insert(next.begin(), next.end());
                if (values.size() > 4096) throw StructureExpansionLimit();
            }
            expansion_visiting.erase(name); return expanded.emplace(name, std::move(values)).first->second;
        };
        expand_part = [&](const D& part) {
            Options values{structural_resources(part)};
            std::vector<std::string> names; V raw = part.get("structural_choices");
            if (raw.nil()) { auto name = optional_text(part, "structural_group"); if (!name.empty()) names.push_back(name); }
            else { A choices(raw); for (int64_t k = 0; k < choices.size(); ++k) names.push_back(choices.at(k).text()); }
            for (const auto& name : names) {
                Options next;
                for (const auto& own : values) for (const auto& tail : expand_group(name)) {
                    std::vector<std::string> resources;
                    std::set_union(own.begin(), own.end(), tail.begin(), tail.end(), std::back_inserter(resources));
                    next.insert(std::move(resources)); if (next.size() > 4096) throw StructureExpansionLimit();
                }
                values = std::move(next);
            }
            return values;
        };
        if (reception_bundles.nil()) {
            A group_names(groups.keys());
            for (int64_t j = 0; j < group_names.size(); ++j) {
                A options(groups.get(group_names.at(j)));
                for (int64_t k = 0; k < options.size(); ++k) reception_part(D(options.at(k)));
            }
        }
        std::set<std::tuple<Pattern, std::vector<std::string>>> unique_bases;
        for (int64_t j = 0; j < bases.size(); ++j) {
            D base(bases.at(j)); if (reception_bundles.nil()) reception_part(base);
            std::vector<std::string> choices; V raw_choices = base.get("structural_choices");
            if (raw_choices.nil()) {
                auto name = optional_text(base, "structural_group"); if (!name.empty()) choices.push_back(name);
            } else {
                A names(raw_choices);
                for (int64_t k = 0; k < names.size(); ++k) choices.push_back(names.at(k).text());
            }
            std::sort(choices.begin(), choices.end());
            unique_bases.emplace(Pattern(structural_resources(base), optional_text(base, "coverage_nurse_id"), optional_text(base, "ward_id")), std::move(choices));
        }
        for (const auto& entry : unique_bases) {
            const auto& base = std::get<0>(entry); const auto& choices = std::get<1>(entry);
            const auto& nurse = std::get<1>(base); const auto& ward = std::get<2>(base);
            if (!nurse.empty() && (ward.empty() || !available("staff:" + nurse))) continue;
            std::vector<int> factor_key;
            for (const auto& group : choices) {
                auto found = prefixes.find(group);
                if (found == prefixes.end()) {
                    const Options& unique = expand_group(group);
                    auto interned = factor_ids.emplace(unique, static_cast<int>(factors.size()));
                    if (interned.second) factors.push_back(unique);
                    found = prefixes.emplace(group, interned.first->second).first;
                }
                factor_key.push_back(found->second);
            }
            std::sort(factor_key.begin(), factor_key.end());
            if (!processed.emplace(base, factor_key).second) continue;
            auto add = [&](const std::vector<std::string>& prefix) {
                const auto& local = std::get<0>(base);
                if (local.empty() && prefix.empty()) return;
                for (const auto* values : {&local, &prefix})
                    for (const auto& resource : *values) if (!available(resource) || (!nurse.empty() && resource == "staff:" + nurse)) return;
                std::vector<std::string> remaining;
                std::set_difference(prefix.begin(), prefix.end(), local.begin(), local.end(), std::back_inserter(remaining));
                terminals[base].insert(std::move(remaining));
            };
            auto combined = combinations.find(factor_key);
            if (combined == combinations.end()) {
                Options values{{}};
                for (int id : factor_key) {
                    Options next;
                    for (const auto& current : values) for (const auto& prefix : factors[id]) {
                        std::vector<std::string> resources;
                        std::set_union(current.begin(), current.end(), prefix.begin(), prefix.end(), std::back_inserter(resources));
                        next.insert(std::move(resources));
                        if (next.size() > 4096) throw StructureExpansionLimit();
                    }
                    values = std::move(next);
                }
                combined = combinations.emplace(factor_key, std::move(values)).first;
            }
            for (const auto& prefix : combined->second) add(prefix);
        }
    }
    D result;
    if (terminals.empty() || reception_edges.empty()) { result.set("pairs", V::number(0)); return result.value(); }
    PackingProgram program;
    std::map<std::string, std::vector<std::pair<int, int>>> exclusivity;
    std::map<std::pair<std::string, std::string>, std::vector<int>> coverage;
    std::vector<int> groups;
    std::set<std::string> all_resources;
    int64_t pattern_count = 0;
    for (const auto& terminal : terminals) {
        all_resources.insert(std::get<0>(terminal.first).begin(), std::get<0>(terminal.first).end());
        for (const auto& prefix : terminal.second) all_resources.insert(prefix.begin(), prefix.end());
        pattern_count += static_cast<int64_t>(terminal.second.size());
    }
    if (all_resources.size() > INT32_MAX) throw std::runtime_error("结构资源规模超出原生索引范围");
    int maximum = static_cast<int>(all_resources.size());
    std::map<Options, std::vector<std::pair<int, int>>> prefix_groups;
    for (const auto& terminal : terminals) {
        const auto& pattern = terminal.first;
        int id = program.integer(std::get<0>(pattern).empty() ? maximum : 1, true); groups.push_back(id);
        for (const auto& resource : std::get<0>(pattern)) exclusivity[resource].emplace_back(id, 1);
        if (!std::get<1>(pattern).empty()) coverage[{std::get<1>(pattern), std::get<2>(pattern)}].push_back(id);
        prefix_groups[terminal.second].emplace_back(id, 1);
    }
    // Identical prefix option sets accept the same incoming terminals. Their
    // integer outgoing flows can therefore be paired with those terminals in
    // any order. Keep the factors instead of materializing every full pair.
    for (const auto& group : prefix_groups) {
        auto flow = group.second;
        for (const auto& prefix : group.first) {
            int id = program.integer(prefix.empty() ? maximum : 1);
            flow.emplace_back(id, -1);
            for (const auto& resource : prefix) exclusivity[resource].emplace_back(id, 1);
        }
        program.equal(std::move(flow));
    }
    for (const auto& nurse_ward : coverage) {
        int cover = program.binary();
        exclusivity["staff:" + nurse_ward.first.first].emplace_back(cover, 1);
        std::vector<std::pair<int, int>> beds{{cover, -static_cast<int>(bed_limit)}};
        for (int id : nurse_ward.second) { program.at_most({{id, 1}, {cover, -1}}, 0); beds.emplace_back(id, 1); }
        program.at_most(std::move(beds), 0);
    }
    for (const auto& row : exclusivity) program.at_most(row.second, 1);
    std::map<std::string, std::vector<std::pair<int, int>>> reception_matching;
    std::vector<std::pair<int, int>> limit;
    for (int id : groups) limit.emplace_back(id, 1);
    for (const auto& edge : reception_edges) {
        int id = program.binary(); limit.emplace_back(id, -static_cast<int>(ratio));
        reception_matching[edge.first].emplace_back(id, 1); reception_matching[edge.second].emplace_back(id, 1);
    }
    for (const auto& row : reception_matching) program.at_most(row.second, 1);
    program.at_most(std::move(limit), 0);
    auto values = program.solve(); int count = 0;
    for (int id : groups) count += values[id];
    result.set("pairs", V::number(count)); result.set("patterns", V::number(pattern_count));
    result.set("structure_encoding", V::text("flat")); result.set("structural_variables", V::number(program.variables.size()));
    result.set("structural_constraints", V::number(program.rows.size()));
    result.set("terminals", V::number(static_cast<int64_t>(terminals.size()))); result.set("prefix_groups", V::number(static_cast<int64_t>(prefix_groups.size())));
    return result.value();
}

struct StructuralGraph {
    struct Node { bool choice; std::vector<std::string> resources; std::vector<int> children; };
    std::vector<Node> nodes;
    std::map<std::string, int> shapes;
    std::map<int, std::set<std::string>> required_resources;
    std::map<std::pair<int, int>, bool> subset_proofs;
    std::map<int, bool> nonempty_paths;
    int intern(Node node) {
        std::sort(node.children.begin(), node.children.end());
        node.children.erase(std::unique(node.children.begin(), node.children.end()), node.children.end());
        std::string key = node.choice ? "o" : "a";
        for (const auto& resource : node.resources) key += std::to_string(resource.size()) + ":" + resource;
        key += "[";
        for (int child : node.children) key += std::to_string(child) + ",";
        key += "]";
        auto found = shapes.find(key);
        if (found != shapes.end()) return found->second;
        int id = static_cast<int>(nodes.size()); shapes.emplace(std::move(key), id); nodes.push_back(std::move(node)); return id;
    }
    int part(const D& source, const D& groups, std::map<std::string, int>& memo, std::set<std::string>& visiting) {
        Node node{false, structural_resources(source), {}};
        std::vector<std::string> names;
        V raw = source.get("structural_choices");
        if (raw.nil()) {
            auto name = optional_text(source, "structural_group"); if (!name.empty()) names.push_back(name);
        } else {
            A choices(raw); for (int64_t i = 0; i < choices.size(); ++i) names.push_back(choices.at(i).text());
        }
        for (const auto& name : names) {
            auto found = memo.find(name);
            if (found == memo.end()) {
                if (!visiting.insert(name).second) throw std::runtime_error("结构选择依赖存在循环");
                V raw_options = groups.get(V::text(name));
                if (raw_options.nil()) throw std::runtime_error("结构配置缺少初诊选项");
                A options(raw_options); Node choice{true, {}, {}};
                for (int64_t i = 0; i < options.size(); ++i) choice.children.push_back(part(D(options.at(i)), groups, memo, visiting));
                visiting.erase(name); found = memo.emplace(name, intern(std::move(choice))).first;
            }
            node.children.push_back(found->second);
        }
        return intern(std::move(node));
    }
    const std::set<std::string>& required(int id) {
        auto found = required_resources.find(id); if (found != required_resources.end()) return found->second;
        const auto& node = nodes[id]; std::set<std::string> result(node.resources.begin(), node.resources.end());
        if (!node.children.empty()) {
            auto shared = required(node.children.front());
            for (size_t i = 1; i < node.children.size(); ++i) {
                const auto& next = required(node.children[i]); std::set<std::string> merged;
                if (node.choice) std::set_intersection(shared.begin(), shared.end(), next.begin(), next.end(), std::inserter(merged, merged.end()));
                else std::set_union(shared.begin(), shared.end(), next.begin(), next.end(), std::inserter(merged, merged.end()));
                shared = std::move(merged);
            }
            result.insert(shared.begin(), shared.end());
        }
        return required_resources.emplace(id, std::move(result)).first->second;
    }
    bool nonempty(int id) {
        auto known = nonempty_paths.find(id); if (known != nonempty_paths.end()) return known->second;
        const auto& node = nodes[id]; bool proof = !node.resources.empty();
        if (!proof && !node.children.empty()) {
            proof = node.choice;
            for (int child : node.children) {
                if (node.choice && !nonempty(child)) { proof = false; break; }
                if (!node.choice && nonempty(child)) { proof = true; break; }
            }
        }
        nonempty_paths.emplace(id, proof); return proof;
    }
    // Sufficient proof of: every complete B resource set contains a complete
    // legal A set. Never infer domination from stage count or an approximate
    // envelope. OR covers every B branch; AND keeps all A requirements.
    // These are positive resource unions only. If child witnesses differ at
    // a shared OR, consistently choose one witnessed complete subtree: all
    // its resources already belong to the same B set. No negative predicate
    // or cross-child exclusion can invalidate that subset witness.
    bool dominates(int a, int b) {
        if (a == b) return true;
        const auto key = std::make_pair(a, b); auto known = subset_proofs.find(key);
        if (known != subset_proofs.end()) return known->second;
        const auto& left = nodes[a]; const auto& right = nodes[b]; bool proof = false;
        if (right.choice) {
            proof = true;
            for (int child : right.children) if (!dominates(a, child)) { proof = false; break; }
        } else {
            // A legal subset of one required B subtree is also a subset of
            // the complete B path. This exposes OR choices below an AND.
            for (int child : right.children) if (dominates(a, child)) { proof = true; break; }
            if (!proof && left.choice) {
                for (int child : left.children) if (dominates(child, b)) { proof = true; break; }
            } else if (!proof) {
                const auto& mandatory = required(b);
                proof = std::includes(mandatory.begin(), mandatory.end(), left.resources.begin(), left.resources.end());
                if (proof) for (int child : left.children) if (!dominates(child, b)) { proof = false; break; }
            }
        }
        subset_proofs.emplace(key, proof); return proof;
    }
    std::vector<int> minimal(const std::set<int>& candidates) {
        std::vector<int> result;
        for (int id : candidates) {
            bool covered = false;
            for (int kept : result) if (nonempty(kept) && dominates(kept, id)) { covered = true; break; }
            if (covered) continue;
            if (nonempty(id)) result.erase(std::remove_if(result.begin(), result.end(), [&](int kept) { return dominates(id, kept); }), result.end());
            result.push_back(id);
        }
        return result;
    }
};

struct StructuralCertificate {
    size_t staff = 0, minimum = 0, upper = 0, lower = 0, matching = 0;
    size_t bound_resources = 0, bound_minimum = 0, bound_upper = 0, bound_subsets = 0;
    std::vector<size_t> root_minimum;
    bool exact = false;
};
StructuralCertificate structural_certificate(const StructuralGraph& graph, const std::vector<std::pair<Pattern, int>>& roots,
        const std::set<int>& reachable,
        const std::set<std::string>& blocked, const std::set<std::pair<std::string, std::string>>& reception,
        size_t ratio, size_t bed_limit, size_t original_upper) {
    // A graph resource is exclusive between complete groups. Coverage nurses
    // are deliberately absent here: one nurse may cover several same-ward beds.
    using Names = std::set<std::string>;
    struct Bound { Names possible, required; size_t minimum = 0; bool feasible = true; };
    StructuralCertificate result;
    Names staff;
    for (const auto& node : graph.nodes) for (const auto& name : node.resources)
        if (name.compare(0, 6, "staff:") == 0) staff.insert(name);
    result.staff = staff.size(); result.upper = original_upper;
    auto prove = [&](const Names& subset, bool root_only = false) {
      std::vector<Bound> bounds(graph.nodes.size());
      // Interning is bottom-up: every child already exists before its parent.
      auto prove_node = [&](size_t id) {
        const auto& node = graph.nodes[id]; auto& bound = bounds[id]; Names own;
        for (const auto& name : node.resources) {
            if (blocked.count(name)) bound.feasible = false;
            if (subset.count(name)) own.insert(name);
        }
        bound.possible = bound.required = own; bound.minimum = own.size();
        if (node.choice) {
            bool first = true; size_t minimum = subset.size() + 1; Names required;
            for (int child : node.children) if (bounds[child].feasible) {
                const auto& next = bounds[child];
                bound.possible.insert(next.possible.begin(), next.possible.end());
                if (first) required = next.required;
                else { Names common; std::set_intersection(required.begin(), required.end(), next.required.begin(), next.required.end(), std::inserter(common, common.end())); required = std::move(common); }
                size_t overlap = 0; for (const auto& name : own) overlap += next.possible.count(name);
                minimum = std::min(minimum, own.size() + (next.minimum > overlap ? next.minimum - overlap : 0));
                first = false;
            }
            if (first) bound.feasible = false; // Empty OR has no complete path.
            else { bound.required.insert(required.begin(), required.end()); bound.minimum = std::max(minimum, bound.required.size()); }
        } else {
            Names disjoint = own; size_t sum = own.size();
            for (int child : node.children) {
                const auto& next = bounds[child];
                bound.feasible = bound.feasible && next.feasible;
                bound.possible.insert(next.possible.begin(), next.possible.end());
                bound.required.insert(next.required.begin(), next.required.end());
                bound.minimum = std::max(bound.minimum, next.minimum);
                bool separate = true; for (const auto& name : next.possible) if (disjoint.count(name)) { separate = false; break; }
                if (separate) { sum += next.minimum; disjoint.insert(next.possible.begin(), next.possible.end()); }
            }
            // Only disjoint possible supports add. Repeated stages or a shared
            // OR can never count the same doctor twice in this lower bound.
            bound.minimum = std::max(bound.minimum, std::max(sum, bound.required.size()));
        }
      };
      if (root_only) for (int id : reachable) prove_node(static_cast<size_t>(id));
      else for (size_t id = 0; id < graph.nodes.size(); ++id) prove_node(id);
      return bounds;
    };
    const auto bounds = prove(staff);
    bool feasible = false; result.minimum = staff.size() + 1;
    for (const auto& root : roots) {
        const auto& bound = bounds[root.second];
        result.root_minimum.push_back(bound.feasible ? bound.minimum : 0);
        if (bound.feasible) { feasible = true; result.minimum = std::min(result.minimum, bound.minimum); }
    }
    if (!feasible) { result.minimum = 0; result.upper = 0; }
    else if (result.minimum) result.upper = std::min(result.upper, staff.size() / result.minimum);

    // Every resource subset gives its own complete-graph packing upper bound.
    // Possible supports supply deterministic candidates without role labels or
    // deleting any path. Extra nurses in H cannot dilute a doctor's bottleneck.
    std::set<Names> subsets;
    if (!staff.empty()) subsets.insert(staff);
    for (const auto& bound : bounds) if (!bound.possible.empty()) subsets.insert(bound.possible);
    result.bound_subsets = subsets.size();
    for (const auto& subset : subsets) {
      auto tighten = [&](const std::vector<Bound>& projected) {
        size_t minimum = subset.size() + 1; bool any = false;
        for (const auto& root : roots) if (projected[root.second].feasible) { any = true; minimum = std::min(minimum, projected[root.second].minimum); }
        if (!any || !minimum) return;
        const size_t upper = subset.size() / minimum;
        if (!result.bound_minimum || upper < result.bound_upper || (upper == result.bound_upper && subset.size() < result.bound_resources)) {
            result.bound_resources = subset.size(); result.bound_minimum = minimum; result.bound_upper = upper;
        }
        result.upper = std::min(result.upper, upper);
      };
      // The first proof supplies every diagnostic subset, including nodes
      // removed by dominance. Later proofs are consumed only at legal roots.
      if (subset == staff) tighten(bounds);
      else tighten(prove(subset, true));
    }

    auto matching = [&](const Names& unavailable) {
        using Graph = boost::adjacency_list<boost::vecS, boost::vecS, boost::undirectedS>;
        using Vertex = boost::graph_traits<Graph>::vertex_descriptor;
        Graph graph;
        std::map<std::string, Vertex> people, desks;
        for (const auto& edge : reception) {
            if (unavailable.count(edge.first) || unavailable.count(edge.second)) continue;
            auto person = people.find(edge.first), desk = desks.find(edge.second);
            if (person == people.end()) person = people.emplace(edge.first, boost::add_vertex(graph)).first;
            if (desk == desks.end()) desk = desks.emplace(edge.second, boost::add_vertex(graph)).first;
            boost::add_edge(person->second, desk->second, graph);
        }
        if (!boost::num_vertices(graph)) return size_t{0};
        std::vector<Vertex> mate(boost::num_vertices(graph), boost::graph_traits<Graph>::null_vertex());
        auto mapping = boost::make_iterator_property_map(mate.begin(), get(boost::vertex_index, graph));
        boost::edmonds_maximum_cardinality_matching(graph, mapping);
        return boost::matching_size(graph, mapping);
    };
    result.matching = matching(blocked);
    result.upper = std::min(result.upper, ratio * result.matching);

    struct Witness { size_t root; Names resources; std::map<int, int> choices; };
    std::vector<Witness> witnesses;
    Names occupied = blocked;
    std::map<std::string, std::pair<std::string, size_t>> covered;
    bool progress = true;
    while (witnesses.size() < result.upper && progress) {
        progress = false;
        for (size_t root = 0; root < roots.size() && witnesses.size() < result.upper; ++root) {
            if (!bounds[roots[root].second].feasible) continue;
            Witness witness{root, {}, {}}; std::set<int> done;
            std::function<bool(int, Witness&, std::set<int>&)> choose = [&](int id, Witness& path, std::set<int>& visited) {
                if (visited.count(id)) return true;
                const auto& node = graph.nodes[id];
                for (const auto& name : node.resources) if (occupied.count(name)) return false;
                path.resources.insert(node.resources.begin(), node.resources.end());
                if (node.choice) {
                    auto prior = path.choices.find(id);
                    if (prior != path.choices.end()) { if (!choose(prior->second, path, visited)) return false; }
                    else {
                        bool found = false;
                        for (int child : node.children) {
                            Witness attempt = path; auto completed = visited; attempt.choices[id] = child;
                            if (choose(child, attempt, completed)) { path = std::move(attempt); visited = std::move(completed); found = true; break; }
                        }
                        if (!found) return false;
                    }
                } else for (int child : node.children) if (!choose(child, path, visited)) return false;
                visited.insert(id); return true;
            };
            if (!choose(roots[root].second, witness, done) || witness.resources.empty()) continue;
            const auto& pattern = roots[root].first; const auto& nurse = std::get<1>(pattern); const auto& ward = std::get<2>(pattern);
            if (!nurse.empty()) {
                const std::string token = "staff:" + nurse; auto prior = covered.find(nurse);
                if (ward.empty() || blocked.count(token) || witness.resources.count(token)) continue;
                if (prior == covered.end()) { if (occupied.count(token)) continue; }
                else if (prior->second.first != ward || prior->second.second >= bed_limit) continue;
            }
            occupied.insert(witness.resources.begin(), witness.resources.end());
            if (!nurse.empty()) { auto& entry = covered[nurse]; entry.first = ward; ++entry.second; occupied.insert("staff:" + nurse); }
            witnesses.push_back(std::move(witness)); progress = true;
        }
    }
    // Independently reconstruct and validate complete witnesses. A greedy
    // miss, a shared-choice inconsistency or insufficient joint reception
    // yields no certificate; the original complete MILP remains the fallback.
    Names used = blocked; std::map<std::string, std::pair<std::string, size_t>> wards;
    bool valid = true;
    for (const auto& witness : witnesses) {
        Names resources; std::set<int> visited; std::vector<int> pending{roots[witness.root].second};
        while (!pending.empty() && valid) {
            int id = pending.back(); pending.pop_back(); if (!visited.insert(id).second) continue;
            const auto& node = graph.nodes[id]; resources.insert(node.resources.begin(), node.resources.end());
            if (node.choice) {
                auto choice = witness.choices.find(id);
                if (choice == witness.choices.end() || std::find(node.children.begin(), node.children.end(), choice->second) == node.children.end()) valid = false;
                else pending.push_back(choice->second);
            } else pending.insert(pending.end(), node.children.begin(), node.children.end());
        }
        if (resources.empty() || resources != witness.resources) valid = false;
        for (const auto& name : resources) if (used.count(name)) valid = false;
        used.insert(resources.begin(), resources.end());
        const auto& pattern = roots[witness.root].first; const auto& nurse = std::get<1>(pattern); const auto& ward = std::get<2>(pattern);
        if (!nurse.empty()) {
            const auto token = "staff:" + nurse; auto prior = wards.find(nurse);
            if (ward.empty() || used.count(token)) valid = false;
            if (prior != wards.end() && (prior->second.first != ward || prior->second.second >= bed_limit)) valid = false;
            auto& entry = wards[nurse]; entry.first = ward; ++entry.second;
        }
    }
    for (const auto& entry : wards) {
        if (used.count("staff:" + entry.first)) valid = false;
        used.insert("staff:" + entry.first);
    }
    const size_t joint_matching = matching(used);
    if (valid && witnesses.size() <= ratio * joint_matching) result.lower = witnesses.size();
    result.exact = valid && result.lower == result.upper;
    return result;
}
V structure_graph(const V& raw_cases, const V& raw_blocked, const V& raw_reception, int64_t bed_limit, int64_t flat_attempt_us) {
    const int64_t started = micros();
    if (bed_limit < 1 || bed_limit > INT32_MAX) throw std::runtime_error("无效的病房覆盖上限");
    D blocked(raw_blocked), reception(raw_reception), people(reception.get("people")), desks(reception.get("desks"));
    const auto blocked_ids = dictionary_names(blocked), people_ids = dictionary_names(people), desk_ids = dictionary_names(desks);
    int64_t ratio = reception.get("ratio").number();
    if (ratio < 1 || ratio > INT32_MAX) throw std::runtime_error("无效的接待结构比例");
    StructuralGraph graph;
    int64_t input_bases = 0, input_group_parts = 0;
    std::map<Pattern, std::set<int>> terminals;
    std::set<std::pair<std::string, std::string>> reception_edges;
    auto reception_part = [&](const D& part) {
        V raw = part.get("resources"); if (raw.nil()) return;
        D values(raw); A keys(values.keys()); std::vector<std::string> local_people, local_desks;
        for (int64_t i = 0; i < keys.size(); ++i) {
            auto name = keys.at(i).text(); if (blocked_ids.count(name)) continue;
            if (people_ids.count(name)) local_people.push_back(name);
            if (desk_ids.count(name)) local_desks.push_back(name);
        }
        for (const auto& person : local_people) for (const auto& desk : local_desks) reception_edges.emplace(person, desk);
    };
    A cases(raw_cases);
    for (int64_t i = 0; i < cases.size(); ++i) {
        D current(cases.at(i)); A bases(current.get("bundles"));
        input_bases += bases.size();
        V raw_groups = current.get("choice_groups"); D groups = raw_groups.nil() ? D() : D(raw_groups);
        A group_names(groups.keys());
        for (int64_t j = 0; j < group_names.size(); ++j) input_group_parts += A(groups.get(group_names.at(j))).size();
        V raw_receptions = current.get("reception_bundles");
        if (!raw_receptions.nil()) {
            A parts(raw_receptions); for (int64_t j = 0; j < parts.size(); ++j) reception_part(D(parts.at(j)));
        } else {
            A names(groups.keys());
            for (int64_t j = 0; j < names.size(); ++j) {
                A parts(groups.get(names.at(j))); for (int64_t k = 0; k < parts.size(); ++k) reception_part(D(parts.at(k)));
            }
        }
        std::map<std::string, int> memo; std::set<std::string> visiting;
        for (int64_t j = 0; j < bases.size(); ++j) {
            D base(bases.at(j)); if (raw_receptions.nil()) reception_part(base);
            auto nurse = optional_text(base, "coverage_nurse_id"), ward = optional_text(base, "ward_id");
            if (!nurse.empty() && (ward.empty() || blocked_ids.count("staff:" + nurse))) continue;
            terminals[Pattern(structural_resources(base), nurse, ward)].insert(graph.part(base, groups, memo, visiting));
        }
    }
    D result;
    if (terminals.empty() || reception_edges.empty()) { result.set("pairs", V::number(0)); return result.value(); }
    std::set<std::string> all_resources;
    for (const auto& node : graph.nodes) all_resources.insert(node.resources.begin(), node.resources.end());
    if (all_resources.size() > INT32_MAX) throw std::runtime_error("结构资源规模超出原生索引范围");
    std::map<std::string, std::vector<std::pair<int, int>>> exclusivity;
    std::map<std::pair<std::string, std::string>, std::vector<int>> coverage;
    std::vector<int> objectives;
    std::vector<std::pair<Pattern, int>> roots;
    std::set<int> reachable;
    std::set<std::string> staff_anchors, facility_anchors;
    bool every_staff = true, every_facility = true;
    int64_t alternatives_before = 0, alternatives_after = 0;
    const int64_t presolve_started = micros();
    for (const auto& terminal : terminals) {
        // K may choose any legal case. For this exact (resources,nurse,ward)
        // Pattern, a complete legal subset replaces a dominated path without
        // increasing any resource use or changing coverage ownership. C and
        // its case probabilities never enter this presolve.
        alternatives_before += terminal.second.size();
        auto choices = graph.minimal(terminal.second); alternatives_after += choices.size();
        int root = graph.intern({true, {}, std::move(choices)});
        roots.emplace_back(terminal.first, root);
        bool has_staff = false, has_facility = false;
        for (const auto& resource : std::get<0>(terminal.first)) {
            if (resource.compare(0, 6, "staff:") == 0) { staff_anchors.insert(resource); has_staff = true; }
            if (resource.compare(0, 9, "facility:") == 0) { facility_anchors.insert(resource); has_facility = true; }
        }
        every_staff = every_staff && has_staff; every_facility = every_facility && has_facility;
    }
    // All roots are now interned. Borrow stable child vectors once and retain
    // one color map across roots; case probabilities never enter K's graph.
    hospital_graph::Reachability reachable_nodes(graph.nodes, [&](int id) { reachable.insert(id); });
    for (const auto& root : roots) reachable_nodes.from(root.second);
    const int64_t presolve_us = micros() - presolve_started;
    const size_t proof_pairs = graph.subset_proofs.size();
    graph.required_resources.clear(); graph.subset_proofs.clear(); graph.nonempty_paths.clear();
    // Each complete group consumes a nonempty resource set. If every terminal
    // consumes a staff/facility anchor, those disjoint anchors give a tighter
    // proven slot bound. This changes the encoding, never the legal candidates.
    size_t slots = all_resources.size();
    if (every_staff) slots = std::min(slots, staff_anchors.size());
    if (every_facility) slots = std::min(slots, facility_anchors.size());
    std::set<std::string> reception_people, reception_desks;
    for (const auto& edge : reception_edges) { reception_people.insert(edge.first); reception_desks.insert(edge.second); }
    slots = std::min(slots, std::min(reception_people.size(), reception_desks.size()) * static_cast<size_t>(ratio));
    const size_t original_slots = slots;
    const int64_t certificate_started = micros();
    const auto certificate = structural_certificate(graph, roots, reachable, blocked_ids, reception_edges, static_cast<size_t>(ratio), static_cast<size_t>(bed_limit), slots);
    const int64_t certificate_us = micros() - certificate_started;
    // This is a proved upper bound over every complete legal path, not a
    // candidate cap. A failed greedy certificate still solves the full graph.
    slots = std::min(slots, certificate.upper);
    result.set("structural_input_cases", V::number(cases.size())); result.set("structural_input_bases", V::number(input_bases));
    result.set("structural_input_group_parts", V::number(input_group_parts));
    result.set("structural_alternatives_before", V::number(alternatives_before)); result.set("structural_alternatives_after", V::number(alternatives_after));
    result.set("structural_dominated_alternatives", V::number(alternatives_before - alternatives_after));
    result.set("structural_interned_nodes", V::number(graph.nodes.size())); result.set("structural_nodes", V::number(reachable.size()));
    result.set("structural_original_slots", V::number(original_slots)); result.set("structural_slots", V::number(slots));
    result.set("structural_flat_attempt_us", V::number(flat_attempt_us)); result.set("structural_presolve_us", V::number(presolve_us));
    result.set("structural_subset_proof_pairs", V::number(proof_pairs)); result.set("structural_certificate_us", V::number(certificate_us));
    result.set("structural_staff_resources", V::number(certificate.staff)); result.set("structural_staff_minimum", V::number(certificate.minimum));
    result.set("structural_bound_resources", V::number(certificate.bound_resources)); result.set("structural_bound_minimum", V::number(certificate.bound_minimum));
    result.set("structural_bound_upper", V::number(certificate.bound_upper)); result.set("structural_bound_subsets", V::number(certificate.bound_subsets));
    result.set("structural_certificate_upper", V::number(certificate.upper)); result.set("structural_certificate_lower", V::number(certificate.lower));
    result.set("structural_reception_matching", V::number(certificate.matching));
    result.set("structural_certificate_status", V::text(certificate.exact ? "optimal" : "fallback"));
    A root_minimum; for (size_t minimum : certificate.root_minimum) root_minimum.append(V::number(minimum));
    result.set("structural_root_staff_minimum", root_minimum.value());
    const char* diagnostic = std::getenv("OGH_CAPACITY_DIAGNOSTIC");
    if (diagnostic && std::string(diagnostic) == "1") {
        std::fprintf(stderr, "OGH_STRUCTURE_CERTIFICATE={\"staff_resources\":%llu,\"minimum_staff\":%llu,\"upper\":%llu,\"lower\":%llu,\"reception_matching\":%llu,\"original_slots\":%llu,\"slots\":%llu,\"exact\":%s,\"certificate_us\":%lld,\"bound_resources\":%llu,\"bound_minimum\":%llu,\"bound_upper\":%llu,\"bound_subsets\":%llu}\n",
            static_cast<unsigned long long>(certificate.staff), static_cast<unsigned long long>(certificate.minimum), static_cast<unsigned long long>(certificate.upper),
            static_cast<unsigned long long>(certificate.lower), static_cast<unsigned long long>(certificate.matching), static_cast<unsigned long long>(original_slots),
            static_cast<unsigned long long>(slots), certificate.exact ? "true" : "false", static_cast<long long>(certificate_us), static_cast<unsigned long long>(certificate.bound_resources),
            static_cast<unsigned long long>(certificate.bound_minimum), static_cast<unsigned long long>(certificate.bound_upper), static_cast<unsigned long long>(certificate.bound_subsets));
        std::fflush(stderr);
    }
    if (certificate.exact) {
        result.set("pairs", V::number(certificate.lower)); result.set("terminals", V::number(terminals.size())); result.set("structure_encoding", V::text("implicit"));
        result.set("structural_variables", V::number(0)); result.set("structural_constraints", V::number(0));
        result.set("structural_assembly_us", V::number(micros() - started)); result.set("structural_solve_us", V::number(0));
        return result.value();
    }
    PackingProgram program;
    std::vector<std::pair<int, int>> previous_order;
    for (size_t slot = 0; slot < slots; ++slot) {
        int selected = program.binary(true); objectives.push_back(selected);
        if (slot) program.at_most({{selected, 1}, {objectives[slot - 1], -1}}, 0);
        std::map<int, int> active;
        std::map<int, std::vector<std::pair<int, int>>> incoming;
        std::map<std::string, std::vector<int>> resource_nodes;
        for (int id : reachable) {
            int variable = program.binary(); active[id] = variable;
            for (const auto& resource : graph.nodes[id].resources) {
                if (blocked_ids.count(resource)) program.at_most({{variable, 1}}, 0);
                resource_nodes[resource].push_back(variable);
            }
        }
        std::vector<std::pair<int, int>> choose{{selected, -1}}, order;
        for (size_t i = 0; i < roots.size(); ++i) {
            int flag = program.binary(); choose.emplace_back(flag, 1); order.emplace_back(flag, static_cast<int>(i + 1));
            incoming[roots[i].second].emplace_back(flag, -1);
            program.at_most({{flag, 1}, {active[roots[i].second], -1}}, 0);
            const auto& pattern = roots[i].first;
            if (!std::get<1>(pattern).empty()) coverage[{std::get<1>(pattern), std::get<2>(pattern)}].push_back(flag);
        }
        program.equal(std::move(choose));
        if (slot) {
            auto symmetry = previous_order;
            for (const auto& item : order) symmetry.emplace_back(item.first, -item.second);
            symmetry.emplace_back(selected, static_cast<int>(roots.size()));
            program.at_most(std::move(symmetry), static_cast<int>(roots.size()));
        }
        previous_order = order;
        for (int id : reachable) {
            const auto& node = graph.nodes[id];
            std::vector<std::pair<int, int>> outgoing{{active[id], -1}};
            for (int child : node.children) {
                int edge = node.choice ? program.binary() : active[id];
                if (node.choice) outgoing.emplace_back(edge, 1);
                incoming[child].emplace_back(edge, -1);
                program.at_most({{edge, 1}, {active[child], -1}}, 0);
            }
            if (node.choice) program.equal(std::move(outgoing));
        }
        for (const auto& item : incoming) {
            auto row = item.second; row.emplace_back(active[item.first], 1); program.at_most(std::move(row), 0);
        }
        std::vector<std::pair<int, int>> nonempty{{selected, 1}};
        for (const auto& item : resource_nodes) {
            int used = program.binary(); exclusivity[item.first].emplace_back(used, 1); nonempty.emplace_back(used, -1);
            for (int variable : item.second) program.at_most({{variable, 1}, {used, -1}}, 0);
            std::vector<std::pair<int, int>> justified{{used, 1}};
            for (int variable : item.second) justified.emplace_back(variable, -1);
            program.at_most(std::move(justified), 0);
        }
        // A slot owns one entire group's resource union. Shared subgraphs do
        // not make one doctor available to different simultaneous groups.
        program.at_most(std::move(nonempty), 0);
    }
    for (const auto& item : coverage) {
        int cover = program.binary(); exclusivity["staff:" + item.first.first].emplace_back(cover, 1);
        std::vector<std::pair<int, int>> beds{{cover, -static_cast<int>(bed_limit)}};
        for (int id : item.second) { program.at_most({{id, 1}, {cover, -1}}, 0); beds.emplace_back(id, 1); }
        program.at_most(std::move(beds), 0);
    }
    for (const auto& row : exclusivity) program.at_most(row.second, 1);
    std::map<std::string, std::vector<std::pair<int, int>>> reception_matching;
    std::vector<std::pair<int, int>> limit;
    for (int id : objectives) limit.emplace_back(id, 1);
    for (const auto& edge : reception_edges) {
        int id = program.binary(); limit.emplace_back(id, -static_cast<int>(ratio));
        reception_matching[edge.first].emplace_back(id, 1); reception_matching[edge.second].emplace_back(id, 1);
    }
    for (const auto& row : reception_matching) program.at_most(row.second, 1);
    program.at_most(std::move(limit), 0);
    const int64_t assembly_us = micros() - started;
    result.set("structural_variables", V::number(program.variables.size())); result.set("structural_constraints", V::number(program.rows.size()));
    result.set("structural_assembly_us", V::number(assembly_us));
    if (diagnostic && std::string(diagnostic) == "1") {
        std::fprintf(stderr, "OGH_STRUCTURE_MODEL={\"input_cases\":%lld,\"input_bases\":%lld,\"input_group_parts\":%lld,\"terminal_patterns\":%llu,\"alternatives_before\":%lld,\"alternatives_after\":%lld,\"dominated\":%lld,\"interned_nodes\":%llu,\"reachable_nodes\":%llu,\"slots\":%llu,\"variables\":%llu,\"constraints\":%llu,\"flat_attempt_us\":%lld,\"presolve_us\":%lld,\"assembly_us\":%lld}\n",
            static_cast<long long>(cases.size()), static_cast<long long>(input_bases), static_cast<long long>(input_group_parts), static_cast<unsigned long long>(terminals.size()),
            static_cast<long long>(alternatives_before), static_cast<long long>(alternatives_after), static_cast<long long>(alternatives_before-alternatives_after),
            static_cast<unsigned long long>(graph.nodes.size()), static_cast<unsigned long long>(reachable.size()), static_cast<unsigned long long>(slots),
            static_cast<unsigned long long>(program.variables.size()), static_cast<unsigned long long>(program.rows.size()), static_cast<long long>(flat_attempt_us), static_cast<long long>(presolve_us), static_cast<long long>(assembly_us));
        std::fflush(stderr);
    }
    const int64_t solve_started = micros();
    auto values = program.solve(); int count = 0;
    result.set("structural_solve_us", V::number(micros() - solve_started));
    for (int id : objectives) count += values[id];
    result.set("pairs", V::number(count)); result.set("terminals", V::number(terminals.size()));
    result.set("structure_encoding", V::text("implicit"));
    return result.value();
}

V structure(const V& raw_cases, const V& raw_blocked, const V& raw_reception, int64_t bed_limit) {
    const int64_t started = micros();
    try { return structure_flat(raw_cases, raw_blocked, raw_reception, bed_limit); }
    catch (const StructureExpansionLimit&) { return structure_graph(raw_cases, raw_blocked, raw_reception, bed_limit, micros()-started); }
}

struct Model {
    mutable std::map<std::string, int64_t> timing;
    std::map<std::string, std::string> locked_roles;
    std::vector<bool> enabled;
    mutable int64_t pricing_calls = 0;
    std::vector<int64_t> columns_per_round;
    std::vector<std::string> resources;
    std::map<std::string, int> resource_ids;
    std::vector<Q> budgets;
    std::vector<Node> nodes;
    std::vector<std::vector<int>> resource_nodes;
    std::map<std::string, int> shapes;
    std::vector<Case> cases;
    std::map<std::string, Q> preparation_fractions;
    int64_t fraction_requests = 0, fraction_hits = 0;
    size_t edge_count = 0, coefficient_count = 0;
    std::unique_ptr<soplex::SoPlex> program;
    std::vector<Column> columns;
    std::vector<std::set<std::string>> known;
    bool dirty = true;
    std::set<int> used_resources;
    int64_t solve_count = 0;
    Q verified_capacity = 0;
    std::string verified_bottleneck;
    std::vector<int> certificate_basis;
    std::vector<Resources> certificate_inverse;
    std::vector<Q> certificate_prices;
    std::vector<Q> certificate_budgets, certificate_values;
    Q certificate_bound = 0;
    std::unique_ptr<PackingProgram> role_program;
    int role_total = -1;
    std::vector<int> role_flow, role_budget_rows;
    std::vector<Q> role_factors;
    Q role_demand = 0, role_limit = -1;
    int role_bottleneck_resource = -1;
    Q role_bottleneck_demand = 0;
    std::vector<std::pair<int, Q>> role_bounds, role_rhs;
    struct ScaledCoefficient { int row, variable; Q factor; };
    std::vector<ScaledCoefficient> role_coefficients;
    std::vector<Q> role_values;
    int64_t role_proof_reuses = 0;
    int64_t role_searches = 0;
    std::map<int, std::string> coverage_owners;
    bool coverage_owners_ready = false;

    Q preparation_fraction(const V& value) {
        ++fraction_requests;
        std::string text = rational_input(value);
        auto found = preparation_fractions.find(text);
        if (found != preparation_fractions.end()) { ++fraction_hits; return found->second; }
        Q parsed(text.c_str()); mpq_canonicalize(parsed.backend().data());
        preparation_fractions.emplace(std::move(text), parsed); return parsed;
    }

    std::string signature(const Resources& values) const {
        std::string result;
        for (const auto& item : values) if (item.second != 0)
            result += std::to_string(item.first) + ":" + item.second.str() + ";";
        return result;
    }
    int intern(Node node) {
        Timer timer(timing, "node_intern_us");
        std::sort(node.children.begin(), node.children.end());
        if (node.choice) node.children.erase(std::unique(node.children.begin(), node.children.end()), node.children.end());
        std::string key = node.choice ? "o" : "a" + signature(node.resources);
        key += "[";
        for (int child : node.children) key += std::to_string(child) + ",";
        key += "]";
        auto found = shapes.find(key);
        if (found != shapes.end()) return found->second;
        edge_count += node.children.size(); coefficient_count += node.resources.size();
        int id = static_cast<int>(nodes.size()); shapes[key] = id; nodes.push_back(std::move(node)); return id;
    }
    int part(const V& input, const D& groups, std::map<std::string, int>& memo, std::set<std::string>& visiting) {
        D source(input); Node node{false, {}, {}};
        V raw_resources = source.get("resources");
        if (!raw_resources.nil()) {
            D values(raw_resources); A keys(values.keys());
            for (int64_t i = 0; i < keys.size(); ++i) {
                V key = keys.at(i); auto resource = resource_ids.find(key.text());
                if (resource == resource_ids.end()) throw std::runtime_error("资源束缺少真实预算");
                Q amount = preparation_fraction(values.get(key));
                if (amount != 0) node.resources[resource->second] = amount;
            }
        }
        V raw_choices = source.get("choices");
        if (!raw_choices.nil()) {
            A choices(raw_choices);
            for (int64_t i = 0; i < choices.size(); ++i) {
                V key = choices.at(i); std::string name = key.text(); auto found = memo.find(name);
                if (found == memo.end()) {
                    if (!visiting.insert(name).second) throw std::runtime_error("资源选择依赖存在循环");
                    V raw_options = groups.get(key);
                    if (raw_options.nil()) throw std::runtime_error("缺少资源选择");
                    A options(raw_options); Node group{true, {}, {}};
                    for (int64_t j = 0; j < options.size(); ++j) group.children.push_back(part(options.at(j), groups, memo, visiting));
                    if (group.children.empty()) throw std::runtime_error("缺少资源选择");
                    visiting.erase(name); found = memo.emplace(name, intern(std::move(group))).first;
                }
                node.children.push_back(found->second);
            }
        }
        return intern(std::move(node));
    }
    Model(const V& raw_cases, const V& raw_budgets) {
        Timer timer(timing, "model_build_us");
        D amounts(raw_budgets); A keys(amounts.keys());
        for (int64_t i = 0; i < keys.size(); ++i) resources.push_back(keys.at(i).text());
        std::sort(resources.begin(), resources.end());
        for (const std::string& resource : resources) {
            resource_ids[resource] = static_cast<int>(budgets.size());
            budgets.push_back(preparation_fraction(amounts.get(resource.c_str())));
        }
        A inputs(raw_cases); std::map<int, int> compact;
        for (int64_t i = 0; i < inputs.size(); ++i) {
            D input(inputs.at(i)); V raw_groups = input.get("choice_groups");
            D no_groups; D groups(raw_groups.nil() ? no_groups.value() : raw_groups);
            std::map<std::string, int> memo; std::set<std::string> visiting;
            A bundles(input.get("bundles")); Node root{true, {}, {}};
            for (int64_t j = 0; j < bundles.size(); ++j) root.children.push_back(part(bundles.at(j), groups, memo, visiting));
            int id = intern(std::move(root)); Q probability = preparation_fraction(input.get("probability"));
            auto found = compact.find(id);
            if (found == compact.end()) {
                int index = static_cast<int>(cases.size()); compact[id] = index;
                cases.push_back(Case{id, 0, {}}); found = compact.find(id);
            }
            Case& target = cases[found->second]; target.probability += probability;
            target.members.push_back(Member{static_cast<int>(i), probability});
        }
        hospital_graph::Reachability reachable_nodes(nodes, [&](int id) {
            for (const auto& value : nodes[id].resources) if (value.second != 0) used_resources.insert(value.first);
        });
        for (const Case& item : cases) if (item.probability > 0) reachable_nodes.from(item.root);
        enabled.assign(nodes.size(), true);
        resource_nodes.resize(resources.size());
        for (size_t i = 0; i < nodes.size(); ++i)
            for (const auto& term : nodes[i].resources) resource_nodes[term.first].push_back(static_cast<int>(i));
        // Parsing reuse owns no hospital model or global state and ends with
        // this complete prepare. Every distinct representation is canonicalized.
        preparation_fractions.clear();
    }
    void update_roles(const V& input) {
        D source(input); A ids(source.keys()); std::map<std::string, std::string> next;
        for (int64_t i = 0; i < ids.size(); ++i) next[ids.at(i).text()] = source.get(ids.at(i)).text();
        if (next == locked_roles) return;
        locked_roles = std::move(next);
        std::vector<bool> local_valid(nodes.size(), true);
        for (const auto& role : locked_roles) {
            std::set<int> own;
            // Use the entire supplied identity as the prefix. In particular,
            // staff IDs containing ':' must retain the original comparison.
            const std::string prefix = "coverage:" + role.first + ":";
            auto first = std::lower_bound(resources.begin(), resources.end(), prefix);
            for (auto current = first; current != resources.end() && current->compare(0, prefix.size(), prefix) == 0; ++current) {
                const bool matches = current->substr(prefix.size()) == role.second;
                for (int node : resource_nodes[static_cast<size_t>(current - resources.begin())]) {
                    if (matches) own.insert(node);
                    else local_valid[node] = false;
                }
            }
            auto staff = resource_ids.find("staff:" + role.first);
            if (staff != resource_ids.end())
                for (int node : resource_nodes[staff->second]) if (!own.count(node)) local_valid[node] = false;
        }
        std::vector<bool> next_enabled(nodes.size());
        for (size_t i = 0; i < nodes.size(); ++i) {
            const Node& node = nodes[i];
            bool children = !node.choice;
            for (int child : node.children) {
                if (node.choice) children = children || next_enabled[child];
                else children = children && next_enabled[child];
            }
            next_enabled[i] = local_valid[i] && children;
        }
        if (next_enabled == enabled) return;
        enabled = std::move(next_enabled); dirty = true; role_demand = 0;
        role_bottleneck_resource = -1;
        // LP columns encode old legal choices. Retain the graph, but rebuild
        // only this relaxation when role restrictions change. MIP rows persist.
        program.reset(); columns.clear(); known.clear(); certificate_basis.clear(); certificate_inverse.clear();
    }
    // Nodes are interned after their children. One exact DP prices every legal
    // implicit AND/OR combination; no Cartesian expansion or column cutoff.
    void price(const std::vector<Q>& prices, std::vector<Q>& costs, std::vector<int>& choices) const {
        Timer timer(timing, "pricing_us"); ++pricing_calls;
        costs.assign(nodes.size(), Q(0)); choices.assign(nodes.size(), -1);
        for (size_t i = 0; i < nodes.size(); ++i) {
            if (!enabled[i]) continue;
            const Node& node = nodes[i];
            if (node.choice) {
                for (int child : node.children) if (enabled[child] && (choices[i] < 0 || costs[child] < costs[i])) {
                    choices[i] = child; costs[i] = costs[child];
                }
            } else {
                for (const auto& value : node.resources) if (prices[value.first] != 0) costs[i] += prices[value.first] * value.second;
                for (int child : node.children) costs[i] += costs[child];
            }
        }
    }
    void expand(int id, const std::vector<int>& choices, Resources& output) const {
        // The chosen graph is a DAG: intern assigns every child before its
        // parent. Propagate exact reference counts before consuming a node,
        // including repeated AND edges; an OR propagates only its chosen edge.
        // Sparse pending counts avoid scanning unrelated nodes for each case.
        std::map<int, Z> pending;
        pending.emplace(id, Z(1));
        while (!pending.empty()) {
            auto current = std::prev(pending.end());
            int next = current->first; Z references = std::move(current->second);
            pending.erase(current);
            const Node& node = nodes[next];
            if (node.choice) {
                if (choices[next] >= 0) pending[choices[next]] += references;
            } else {
                if (references == 1) {
                    for (const auto& item : node.resources) output[item.first] += item.second;
                } else if (!node.resources.empty()) {
                    Q factor(references);
                    for (const auto& item : node.resources) output[item.first] += item.second * factor;
                }
                for (int child : node.children) pending[child] += references;
            }
        }
    }
    V resource_values(const Resources& values) const {
        D result;
        for (const auto& item : values) if (item.second != 0) result.set(resources[item.first].c_str(), fraction(item.second));
        return result.value();
    }
    void update_budgets(const V& values) {
        D input(values);
        std::map<std::string, Q> parsed;
        for (size_t i = 0; i < resources.size(); ++i) {
            std::string text = rational_input(input.get(resources[i].c_str()));
            auto found = parsed.find(text);
            if (found == parsed.end()) {
                Q next(text.c_str()); mpq_canonicalize(next.backend().data());
                found = parsed.emplace(std::move(text), std::move(next)).first;
            }
            const Q& next = found->second;
            if (next < 0) throw std::runtime_error("资源预算不能为负");
            if (next == budgets[i]) continue;
            if (program && used_resources.count(static_cast<int>(i))) program->changeRhsRational(static_cast<int>(cases.size() + i), next);
            budgets[i] = next;
            if (used_resources.count(static_cast<int>(i))) dirty = true;
        }
    }
    V summary() const {
        D result; result.set("capacity", fraction(verified_capacity));
        result.set("bottleneck", V::text(verified_bottleneck)); result.set("resource_count", V::number(resources.size()));
        result.set("bundle_count", V::number(columns.size()));
        result.set("bottleneck_kind", V::text("exhausted_resource"));
        result.set("used_resource_count", V::number(used_resources.size()));
        result.set("node_count", V::number(nodes.size()));
        result.set("edge_count", V::number(edge_count)); result.set("coefficient_count", V::number(coefficient_count));
        result.set("prepare_fraction_requests", V::number(fraction_requests)); result.set("prepare_fraction_hits", V::number(fraction_hits));
        result.set("resolution_count", V::number(solve_count));
        result.set("pricing_calls", V::number(pricing_calls));
        auto measured = timing;
        measured["variant_and_graph_input_us"] = measured["model_build_us"] - measured["node_intern_us"];
        result.set("timing_us", timing_values(measured));
        A rounds; for (int64_t count : columns_per_round) rounds.append(V::number(count));
        result.set("columns_per_round", rounds.value());
        result.set("lp_rounds", V::number(columns_per_round.size()));
        size_t inverse_nonzeros = 0; for (const auto& column : certificate_inverse) inverse_nonzeros += column.size();
        result.set("certificate_nonzeros", V::number(inverse_nonzeros));
        result.set("solver_kind", V::text(role_program ? "nursing_mip" : "lp"));
        if (role_program) {
            result.set("mip_variables", V::number(role_program->variables.size()));
            result.set("mip_constraints", V::number(role_program->rows.size()));
            result.set("mip_integral_variables", V::number(std::count(role_program->integral.begin(), role_program->integral.end(), true)));
            result.set("exact_polishes", V::number(role_program->exact_polishes));
            result.set("proof_reuses", V::number(role_proof_reuses));
            result.set("mip_searches", V::number(role_searches));
            result.set("nursing_timing_us", timing_values(role_program->timing));
        }
        return result.value();
    }
    bool feasible(const Q& capacity, const std::vector<Q>& amounts, const std::vector<Q>& used) const {
        if (capacity < 0) return false;
        for (size_t i = 0; i < cases.size(); ++i) if (amounts[i] != capacity * cases[i].probability) return false;
        for (size_t i = 0; i < resources.size(); ++i) if (used[i] > budgets[i]) return false;
        return true;
    }
    void publish(const Q& capacity, const std::vector<Q>& used) {
        verified_capacity = capacity; verified_bottleneck.clear();
        for (size_t i = 0; i < resources.size(); ++i) if (used_resources.count(static_cast<int>(i)) && used[i] > 0 && used[i] == budgets[i]) { verified_bottleneck = resources[i]; break; }
        dirty = false;
    }
    void retain_certificate(const std::vector<Q>& prices) {
        Timer timer(timing, "certificate_build_us");
        soplex::DataArray<int> basis;
        certificate_basis.clear(); certificate_inverse.clear();
        if (!program->getBasisIndRational(basis)) return;
        for (int i = 0; i < basis.size(); ++i) certificate_basis.push_back(basis[i]);
        certificate_inverse.resize(resources.size());
        for (size_t i = 0; i < resources.size(); ++i) {
            soplex::SSVectorRational column(static_cast<int>(certificate_basis.size()));
            if (!program->getBasisInverseColRational(static_cast<int>(cases.size() + i), column)) {
                certificate_basis.clear(); certificate_inverse.clear(); return;
            }
            for (size_t row = 0; row < certificate_basis.size(); ++row)
                if (column[static_cast<int>(row)] != 0) certificate_inverse[i][static_cast<int>(row)] = column[static_cast<int>(row)];
        }
        certificate_prices = prices;
        certificate_budgets = budgets;
        certificate_values.assign(certificate_basis.size(), Q(0)); certificate_bound = 0;
        for (size_t i = 0; i < resources.size(); ++i) {
            certificate_bound += budgets[i] * prices[i];
            for (const auto& entry : certificate_inverse[i]) certificate_values[entry.first] += entry.second * budgets[i];
        }
    }
    bool reuse_certificate() {
        Timer timer(timing, "certificate_check_us");
        if (certificate_basis.empty()) return false;
        // RHS changes leave A, the objective and all implicit-choice dual
        // inequalities unchanged. SoPlex supplies the exact inverse columns.
        // A feasible B^-1*b matching that dual bound proves the new optimum.
        std::vector<Q> values = certificate_values;
        Q bound = certificate_bound;
        for (size_t i = 0; i < resources.size(); ++i) {
            Q delta = budgets[i] - certificate_budgets[i];
            if (delta == 0) continue;
            bound += delta * certificate_prices[i];
            for (const auto& item : certificate_inverse[i]) values[item.first] += item.second * delta;
        }
        std::vector<Q> amounts(cases.size(), Q(0)), used(resources.size(), Q(0));
        Q capacity = 0;
        for (size_t i = 0; i < values.size(); ++i) {
            if (values[i] < 0) return false;
            int variable = certificate_basis[i];
            if (variable == 0) capacity = values[i];
            else if (variable > 0 && values[i] != 0) {
                const Column& column = columns[static_cast<size_t>(variable - 1)];
                amounts[column.case_index] += values[i];
                for (const auto& item : column.resources) used[item.first] += values[i] * item.second;
            }
        }
        if (!feasible(capacity, amounts, used) || capacity != bound) return false;
        certificate_values = values; certificate_budgets = budgets; certificate_bound = bound;
        publish(capacity, used); return true;
    }
    Q role_priced_budget(const std::vector<Q>& prices) const {
        Q result = 0;
        std::map<std::string, Q> coverage_max;
        for (int resource : used_resources) {
            Q weighted = prices[resource] * budgets[resource];
            auto owner = coverage_owners.find(resource);
            if (owner == coverage_owners.end()) result += weighted;
            else if (weighted > coverage_max[owner->second]) coverage_max[owner->second] = weighted;
        }
        for (const auto& item : coverage_max) result += item.second;
        return result;
    }
    V solve_roles() {
        if (!coverage_owners_ready) {
            for (int resource : used_resources) {
                const std::string& name = resources[resource];
                if (name.compare(0, 9, "coverage:") != 0) continue;
                auto separator = name.find(':', 9);
                if (separator == std::string::npos) throw std::runtime_error("护理岗位缺少病房身份");
                coverage_owners[resource] = name.substr(9, separator - 9);
            }
            coverage_owners_ready = true;
        }
        // A unit-priced complete path gives a true lower bound on total demand
        // per Visit. It derives all flow bounds from this hospital's budgets;
        // there is no arbitrary Visit, branch or candidate limit.
        if (role_demand == 0) {
            std::vector<Q> prices(resources.size(), Q(1)), costs;
            std::vector<int> choices;
            price(prices, costs, choices);
            for (const Case& item : cases) role_demand += item.probability * costs[item.root];
        }
        if (role_factors.empty()) {
            role_factors.assign(nodes.size(), Q(0));
            for (const Case& item : cases) role_factors[item.root] += item.probability;
            for (size_t i = nodes.size(); i-- > 0;)
                for (int child : nodes[i].children) role_factors[child] += role_factors[i];
        }
        Q budget = 0;
        for (int resource : used_resources) {
            const Q& amount = budgets[resource];
            if (amount < 0) throw std::runtime_error("资源预算不能为负");
            budget += amount;
        }
        if (role_demand <= 0) throw std::runtime_error("岗位容量缺少有限资源上界");
        Q limit = budget / role_demand;
        // Every nonnegative price vector prices the complete implicit graph.
        // These bounds remain valid after redistribution and role changes.
        auto demand_at = [&](const std::vector<Q>& prices) {
            std::vector<Q> costs; std::vector<int> choices; price(prices, costs, choices);
            Q demand = 0;
            for (const Case& item : cases) demand += item.probability * costs[item.root];
            return demand;
        };
        auto tighten = [&](const std::vector<Q>& prices, const Q& demand) {
            Q value = role_priced_budget(prices);
            if (demand > 0) { Q bound = value / demand; if (bound < limit) limit = bound; }
        };
        std::vector<Q> prices(resources.size(), Q(0));
        for (int resource : used_resources) prices[resource] = budgets[resource] > 0 ? Q(1) / budgets[resource] : Q(1);
        tighten(prices, demand_at(prices));
        auto bottleneck = resource_ids.find(verified_bottleneck);
        if (bottleneck != resource_ids.end()) {
            std::fill(prices.begin(), prices.end(), Q(0)); prices[bottleneck->second] = 1;
            if (role_bottleneck_resource != bottleneck->second) {
                role_bottleneck_demand = demand_at(prices);
                role_bottleneck_resource = bottleneck->second;
            }
            tighten(prices, role_bottleneck_demand);
        }
        const auto& factors = role_factors;

        if (!role_program) {
            std::vector<Q> upper;
            for (const Q& factor : factors) upper.push_back(factor * limit);
            role_program.reset(new PackingProgram);
            PackingProgram& mip = *role_program;
            role_total = mip.continuous(limit, true);
            int total = role_total;
            role_bounds.emplace_back(total, Q(1));
            std::vector<int> flow;
            for (size_t i = 0; i < upper.size(); ++i) {
                flow.push_back(mip.continuous(upper[i]));
                role_bounds.emplace_back(flow.back(), factors[i]);
            }
            role_flow = flow;
            std::vector<std::vector<std::pair<int, Q>>> incoming(nodes.size()), usage(resources.size());
            for (size_t i = 0; i < nodes.size(); ++i) {
                const Node& node = nodes[i];
                incoming[i].emplace_back(flow[i], Q(-1));
                if (node.choice) {
                    std::vector<std::pair<int, Q>> outgoing{{flow[i], Q(-1)}};
                    for (int child : node.children) {
                        int edge = mip.continuous(upper[i]);
                        role_bounds.emplace_back(edge, factors[i]);
                        outgoing.emplace_back(edge, Q(1)); incoming[child].emplace_back(edge, Q(1));
                    }
                    mip.equal_rational(std::move(outgoing));
                } else {
                    for (int child : node.children) incoming[child].emplace_back(flow[i], Q(1));
                }
                for (const auto& item : node.resources) usage[item.first].emplace_back(flow[i], item.second);
            }
            for (const Case& item : cases) incoming[item.root].emplace_back(total, item.probability);
            for (auto& row : incoming) mip.equal_rational(std::move(row));
            for (size_t i = 0; i < resources.size(); ++i) role_budget_rows.push_back(mip.less_equal(std::move(usage[i]), budgets[i]));

            std::map<int, int> coverage;
            std::map<std::string, std::vector<int>> nurses;
            for (const auto& owner : coverage_owners) {
                int role = mip.binary(); coverage[owner.first] = role;
                nurses[owner.second].push_back(role);
            }
            for (const auto& nurse : nurses) {
                std::vector<std::pair<int, int>> roles;
                for (int role : nurse.second) roles.emplace_back(role, 1);
                mip.at_most(std::move(roles), 1);
            }
            for (size_t i = 0; i < nodes.size(); ++i) {
                std::set<std::string> own;
                for (const auto& item : nodes[i].resources) {
                    auto role = coverage.find(item.first);
                    if (role == coverage.end()) continue;
                    own.insert(coverage_owners.at(item.first));
                    int row = mip.less_equal({{flow[i], Q(1)}, {role->second, -upper[i]}}, Q(0));
                    role_coefficients.push_back({row, role->second, -factors[i]});
                }
                for (const auto& item : nodes[i].resources) {
                    const std::string& name = resources[item.first];
                    if (name.compare(0, 6, "staff:") != 0) continue;
                    std::string id = name.substr(6);
                    auto nurse = nurses.find(id);
                    if (nurse == nurses.end() || own.count(id)) continue;
                    std::vector<std::pair<int, Q>> exclusive{{flow[i], Q(1)}};
                    for (int role : nurse->second) exclusive.emplace_back(role, upper[i]);
                    int row = mip.less_equal(std::move(exclusive), upper[i]);
                    role_rhs.emplace_back(row, factors[i]);
                    for (int role : nurse->second) role_coefficients.push_back({row, role, factors[i]});
                }
            }
        } else {
            // Keep the original exact model. SCIP's transformed search state
            // belongs to the old RHS; discard it before changing original data.
            role_program->reopen();
            for (size_t i = 0; i < budgets.size(); ++i) role_program->change_upper(role_budget_rows[i], budgets[i]);
            if (role_limit != limit) {
                for (const auto& bound : role_bounds) role_program->change_bound(bound.first, bound.second * limit);
                for (const auto& row : role_rhs) role_program->change_upper(row.first, row.second * limit);
                for (const auto& term : role_coefficients) role_program->change_coefficient(term.row, term.variable, term.factor * limit);
            }
        }
        role_limit = limit;
        PackingProgram& mip = *role_program;
        for (size_t i = 0; i < role_flow.size(); ++i) mip.change_bound(role_flow[i], enabled[i] ? factors[i] * limit : Q(0));
        const auto& flow = role_flow;
        int total = role_total;
        std::vector<Q> values;
        if (!role_values.empty() && role_values[total] > 0) {
            // Unit-priced complete-path demand is a current global upper bound.
            // Scale continuous flow only; keep every integer role unchanged.
            // Feasibility at that bound is a complete L=U proof, otherwise search.
            values = role_values;
            const Q factor = limit / role_values[total];
            for (size_t i = 0; i < values.size(); ++i) if (!mip.integral[i]) values[i] *= factor;
            if (values[total] != limit || !mip.valid_values(values)) values.clear();
            else ++role_proof_reuses;
        }
        if (values.empty()) { ++role_searches; values = mip.solve_rational(); }
        std::vector<Q> amounts, used(resources.size(), Q(0));
        for (const Case& item : cases) amounts.push_back(values[flow[item.root]]);
        for (size_t i = 0; i < nodes.size(); ++i)
            for (const auto& item : nodes[i].resources) used[item.first] += values[flow[i]] * item.second;
        if (!feasible(values[total], amounts, used)) throw std::runtime_error("精确岗位流违反病例或资源约束");
        role_values = values;
        publish(values[total], used);
        return summary();
    }
    V solve(bool allocations = true) {
        if (cases.empty()) return allocations ? empty() : summary();
        for (const Case& item : cases) if (item.probability > 0 && (nodes[item.root].children.empty() || !enabled[item.root])) {
            publish(Q(0), std::vector<Q>(resources.size(), Q(0))); return summary();
        }
        if (!allocations && !dirty) return summary();
        ++solve_count;
        if (!allocations) for (int resource : used_resources)
            if (resources[resource].compare(0, 9, "coverage:") == 0) return solve_roles();
        if (!allocations && program && reuse_certificate()) return summary();
        using namespace soplex;
        bool initialize = !program;
        if (initialize) program.reset(new SoPlex);
        SoPlex& lp = *program;
        if (initialize) {
            lp.setIntParam(SoPlex::VERBOSITY, 0);
            lp.setIntParam(SoPlex::OBJSENSE, SoPlex::OBJSENSE_MAXIMIZE);
            lp.setIntParam(SoPlex::SYNCMODE, SoPlex::SYNCMODE_AUTO);
            lp.setIntParam(SoPlex::SOLVEMODE, SoPlex::SOLVEMODE_RATIONAL);
            lp.setIntParam(SoPlex::CHECKMODE, SoPlex::CHECKMODE_RATIONAL);
            lp.setRealParam(SoPlex::FEASTOL, 0.0); lp.setRealParam(SoPlex::OPTTOL, 0.0);
            for (size_t i = 0; i < cases.size(); ++i) lp.addRowRational(LPRowRational(0, DSVectorRational(), 0));
            for (const Q& budget : budgets) lp.addRowRational(LPRowRational(-infinity, DSVectorRational(), budget));
            DSVectorRational q_column;
            for (size_t i = 0; i < cases.size(); ++i) q_column.add(static_cast<int>(i), -cases[i].probability);
            lp.addColRational(LPColRational(1, q_column, infinity, 0));
            known.resize(cases.size());
        }
        auto add_column = [&](int index, const Resources& values, const std::string& key) {
            DSVectorRational column; column.add(index, Q(1));
            for (const auto& item : values) if (item.second != 0) column.add(static_cast<int>(cases.size()) + item.first, item.second);
            lp.addColRational(LPColRational(0, column, infinity, 0));
            known[index].insert(key); columns.push_back(Column{index, values});
        };
        std::vector<Q> prices(resources.size(), Q(0)), costs; std::vector<int> choices;
        if (initialize) {
            price(prices, costs, choices);
            for (size_t i = 0; i < cases.size(); ++i) { Resources values; expand(cases[i].root, choices, values); add_column(static_cast<int>(i), values, signature(values)); }
        }
        VectorRational dual(static_cast<int>(cases.size() + resources.size()));
        for (;;) {
            int status;
            { Timer timer(timing, "lp_optimize_us"); status = lp.optimize(); }
            if (status != SPxSolver::OPTIMAL) throw std::runtime_error("精确容量LP未取得最优解，状态=" + std::to_string(status));
            if (!lp.getDualRational(dual)) throw std::runtime_error("精确容量LP缺少对偶解");
            for (size_t i = 0; i < resources.size(); ++i) prices[i] = dual[static_cast<int>(cases.size() + i)];
            price(prices, costs, choices); int64_t added = 0;
            for (size_t i = 0; i < cases.size(); ++i) {
                if (dual[static_cast<int>(i)] + costs[cases[i].root] >= 0) continue;
                Resources values; expand(cases[i].root, choices, values);
                auto key = signature(values);
                if (known[i].count(key)) throw std::runtime_error("重复资源束仍有负约化成本");
                add_column(static_cast<int>(i), values, key); ++added;
            }
            columns_per_round.push_back(added);
            if (!added) break;
        }
        VectorRational primal(lp.numColsRational());
        if (!lp.getPrimalRational(primal)) throw std::runtime_error("精确容量LP缺少原始解");
        Q capacity = primal[0], dual_value = 0, q_price = 0;
        std::vector<Q> amounts(cases.size(), Q(0)), used(resources.size(), Q(0));
        for (size_t i = 0; i < columns.size(); ++i) {
            Q amount = primal[static_cast<int>(i + 1)];
            if (amount < 0) throw std::runtime_error("精确容量LP产生负分配");
            amounts[columns[i].case_index] += amount;
            for (const auto& item : columns[i].resources) used[item.first] += amount * item.second;
        }
        for (size_t i = 0; i < cases.size(); ++i) q_price -= cases[i].probability * dual[static_cast<int>(i)];
        for (size_t i = 0; i < resources.size(); ++i) {
            if (prices[i] < 0) throw std::runtime_error("精确容量LP对偶预算校验失败");
            dual_value += budgets[i] * prices[i];
        }
        if (!feasible(capacity, amounts, used) || q_price < 1 || capacity != dual_value) throw std::runtime_error("精确容量LP最优性校验失败");
        publish(capacity, used);
        // The hospital consumes a capacity projection, not hypothetical Visit
        // allocations. Keep the exact certificate native; materialize full
        // assignments only for the one-shot allocation interface.
        if (!allocations) { retain_certificate(prices); return summary(); }
        A assignments;
        for (size_t i = 0; i < columns.size(); ++i) {
            Q amount = primal[static_cast<int>(i + 1)]; if (amount == 0) continue;
            const Column& column = columns[i]; const Case& item = cases[column.case_index];
            V values = resource_values(column.resources);
            for (const Member& member : item.members) {
                D assignment; assignment.set("case_index", V::number(member.index));
                assignment.set("resources", values); assignment.set("amount", fraction(amount * member.probability / item.probability));
                assignments.append(assignment.value());
            }
        }
        D result(summary()); result.set("assignments", assignments.value()); return result.value();
    }
};

V calculate_fraction(int operation, const V& first, const V& second) {
    Q a = rational(first), b = rational(second), result;
    switch (operation) {
        case 0: result = a; break;
        case 1: result = a + b; break;
        case 2: result = a - b; break;
        case 3: result = a * b; break;
        case 4: if (b == 0) throw std::runtime_error("分数除数为零"); result = a / b; break;
        case 5: result = a == b ? 0 : a < b ? -1 : 1; break;
        default: throw std::runtime_error("未知分数运算");
    }
    return fraction(result);
}
V calculate_integer(int operation, const V& first, const V& second) {
    Z a(first.text().c_str()), b(second.text().c_str()), result, remainder;
    switch (operation) {
        case 0: result = a + b; break;
        case 1: result = a * b; break;
        case 2: case 3:
            if (b == 0) throw std::runtime_error("整数除数为零");
            mpz_tdiv_qr(result.backend().data(), remainder.backend().data(), a.backend().data(), b.backend().data()); break;
        case 4: mpz_gcd(result.backend().data(), a.backend().data(), b.backend().data()); break;
        case 5: result = a == b ? 0 : a < b ? -1 : 1; break;
        default: throw std::runtime_error("未知整数运算");
    }
    D output; output.set("value", V::text(result.str())); output.set("remainder", V::text(remainder.str())); return output.value();
}
#include "platform_spatial_index.h"
#include "platform_route_queue.h"
#include "platform_bed_matching.h"
#include "platform_grid_component.h"
#include "platform_route_search.h"
#include "platform_json_stream.inc"
#include "platform_backup_zip.h"
struct CapacityInstance { std::unique_ptr<Model> model; };
struct AggregateFractions {
    std::map<std::string, Q> parsed;
    Q read(const V& value) {
        // Validate every occurrence before lookup. Only this exact complete
        // legal representation can reuse a canonical GMP value in this batch.
        std::string text = rational_input(value);
        auto found = parsed.find(text);
        if (found == parsed.end()) {
            Q next(text.c_str()); mpq_canonicalize(next.backend().data());
            found = parsed.emplace(std::move(text), std::move(next)).first;
        }
        return found->second;
    }
};
V aggregate_stages(const V& raw_stages, const V& raw_weight, AggregateFractions* fractions = nullptr) {
    D stages(raw_stages), output, weighted, totals;
    Q weight = fractions ? fractions->read(raw_weight) : rational(raw_weight);
    std::map<std::string, Q> resources;
    A names(stages.keys());
    for (int64_t i = 0; i < names.size(); ++i) {
        V name = names.at(i); D stage(stages.get(name)), values;
        A ids(stage.keys());
        for (int64_t j = 0; j < ids.size(); ++j) {
            V id = ids.at(j); V value = stage.get(id);
            Q amount = (fractions ? fractions->read(value) : rational(value)) * weight;
            resources[id.text()] += amount;
            values.set(id.text().c_str(), fraction(amount));
        }
        weighted.set(name.text().c_str(), values.value());
    }
    for (const auto& item : resources) totals.set(item.first.c_str(), fraction(item.second));
    output.set("stage_resources", weighted.value()); output.set("resources", totals.value());
    return output.value();
}
GDExtensionObjectPtr create_model(void*, GDExtensionBool notify) {
    auto* instance = new CapacityInstance;
    auto object = construct_object(&ref_class);
    set_instance(object, &model_class, instance);
    if (notify) {
        int64_t postinitialize = 0; GDExtensionBool reversed = 0;
        const void* args[] = {&postinitialize, &reversed}; object_ptrcall(notification, object, args, nullptr);
    }
    return object;
}
void free_model(void*, GDExtensionClassInstancePtr instance) {
    std::lock_guard<std::recursive_mutex> guard(discrete_mutex);
    delete static_cast<CapacityInstance*>(instance);
}
enum Method { SOLVE, FRACTION, INTEGER, STRUCTURE, AGGREGATE, AGGREGATE_COMPONENTS, THREAD_CPU, MONOTONIC_CLOCK, PERSONAL_BED_MATCHING, GRID_COMPONENT, ROUTE_SEARCH, PREPARE_MODEL, SOLVE_MODEL, PREPARE_ROLES, SOLVE_ROLES };
struct MethodInfo { const char* name; Method method; std::vector<GDExtensionVariantType> arguments; };
MethodInfo methods[] = {
    {"route_search", ROUTE_SEARCH, {GDEXTENSION_VARIANT_TYPE_DICTIONARY}},
    {"grid_component", GRID_COMPONENT, {GDEXTENSION_VARIANT_TYPE_ARRAY, GDEXTENSION_VARIANT_TYPE_ARRAY, GDEXTENSION_VARIANT_TYPE_ARRAY, GDEXTENSION_VARIANT_TYPE_BOOL}},
    {"personal_bed_matching", PERSONAL_BED_MATCHING, {GDEXTENSION_VARIANT_TYPE_ARRAY, GDEXTENSION_VARIANT_TYPE_DICTIONARY}},
    {"solve", SOLVE, {GDEXTENSION_VARIANT_TYPE_ARRAY, GDEXTENSION_VARIANT_TYPE_DICTIONARY}},
    {"fraction", FRACTION, {GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_DICTIONARY, GDEXTENSION_VARIANT_TYPE_DICTIONARY}},
    {"integer", INTEGER, {GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_STRING, GDEXTENSION_VARIANT_TYPE_STRING}},
    {"structure", STRUCTURE, {GDEXTENSION_VARIANT_TYPE_ARRAY, GDEXTENSION_VARIANT_TYPE_DICTIONARY, GDEXTENSION_VARIANT_TYPE_DICTIONARY, GDEXTENSION_VARIANT_TYPE_INT}},
    {"aggregate_stages", AGGREGATE, {GDEXTENSION_VARIANT_TYPE_DICTIONARY, GDEXTENSION_VARIANT_TYPE_DICTIONARY}},
    {"aggregate_components", AGGREGATE_COMPONENTS, {GDEXTENSION_VARIANT_TYPE_ARRAY}},
    {"thread_cpu", THREAD_CPU, {}},
    {"monotonic_clock", MONOTONIC_CLOCK, {}},
    {"prepare", PREPARE_MODEL, {GDEXTENSION_VARIANT_TYPE_ARRAY, GDEXTENSION_VARIANT_TYPE_DICTIONARY}},
    {"solve", SOLVE_MODEL, {GDEXTENSION_VARIANT_TYPE_DICTIONARY}},
    {"prepare_with_roles", PREPARE_ROLES, {GDEXTENSION_VARIANT_TYPE_ARRAY, GDEXTENSION_VARIANT_TYPE_DICTIONARY, GDEXTENSION_VARIANT_TYPE_DICTIONARY}},
    {"solve_with_roles", SOLVE_ROLES, {GDEXTENSION_VARIANT_TYPE_DICTIONARY, GDEXTENSION_VARIANT_TYPE_DICTIONARY}}
};
V invoke(Method method, const std::vector<V>& args, GDExtensionClassInstancePtr instance) {
    try {
        if (method == PERSONAL_BED_MATCHING) return solve_personal_bed_matching(args[0], args[1]);
        if (method == GRID_COMPONENT) return solve_grid_component(args[0], args[1], args[2], args[3]);
        if (method == ROUTE_SEARCH) return solve_route_search(args[0]);
        std::unique_lock<std::recursive_mutex> discrete_guard(discrete_mutex, std::defer_lock);
        int64_t lock_started = micros();
        if (method == SOLVE || method == STRUCTURE || method >= PREPARE_MODEL) discrete_guard.lock();
        int64_t lock_wait = micros() - lock_started;
        if (method == SOLVE) return Model(args[0], args[1]).solve();
        if (method == FRACTION) return calculate_fraction(static_cast<int>(args[0].number()), args[1], args[2]);
        if (method == STRUCTURE) return structure(args[0], args[1], args[2], args[3].number());
        if (method == AGGREGATE) return aggregate_stages(args[0], args[1]);
        if (method == AGGREGATE_COMPONENTS) {
            A requests(args[0]), results;
            AggregateFractions fractions;
            for (int64_t i = 0; i < requests.size(); ++i) {
                D request(requests.at(i));
                results.append(aggregate_stages(request.get("stages"), request.get("weight"), &fractions));
            }
            D output; output.set("components", results.value()); return output.value();
        }
        if (method == MONOTONIC_CLOCK) {
            int64_t ticks, frequency;
            if (!ogh_monotonic_clock(&ticks, &frequency)) return failure("单调时钟不可用");
            D result; result.set("qpc_ticks", V::number(ticks)); result.set("qpc_frequency", V::number(frequency));
            return result.value();
        }
        if (method == THREAD_CPU) {
            uint64_t elapsed = ogh_current_thread_cpu_us();
            if (elapsed == UINT64_MAX) return failure("线程 CPU 时间不可用");
            D result; result.set("cpu_us", V::number(static_cast<int64_t>(elapsed)));
            return result.value();
        }
        if (method >= PREPARE_MODEL) {
            auto& capacity = *static_cast<CapacityInstance*>(instance);
            if (method == PREPARE_MODEL || method == PREPARE_ROLES) {
                capacity.model.reset(new Model(args[0], args[1]));
                if (method == PREPARE_ROLES) capacity.model->update_roles(args[2]);
            }
            else {
                if (!capacity.model) throw std::runtime_error("容量模型尚未准备");
                capacity.model->update_budgets(args[0]);
                if (method == SOLVE_ROLES) capacity.model->update_roles(args[1]);
            }
            capacity.model->timing["lock_wait_us"] += lock_wait;
            return capacity.model->solve(false);
        }
        return calculate_integer(static_cast<int>(args[0].number()), args[1], args[2]);
    } catch (const std::exception& error) {
        if (method >= PREPARE_MODEL) {
            std::lock_guard<std::recursive_mutex> guard(discrete_mutex);
            static_cast<CapacityInstance*>(instance)->model.reset();
        }
        return failure(error.what());
    }
}
void call(void* userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr* args,
          GDExtensionInt count, GDExtensionVariantPtr returned, GDExtensionCallError* error) {
    auto& method = *static_cast<MethodInfo*>(userdata); error->error = GDEXTENSION_CALL_OK;
    std::vector<V> values;
    if (count != static_cast<int64_t>(method.arguments.size())) { error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; return; }
    for (int64_t i = 0; i < count; ++i) {
        if (type(args[i]) != method.arguments[i]) { error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; error->argument = static_cast<int32_t>(i); error->expected = method.arguments[i]; return; }
        values.emplace_back(args[i]);
    }
    V result = invoke(method.method, values, instance); destroy(returned); new_copy(returned, &result.raw);
}
void ptrcall(void* userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstTypePtr* args, GDExtensionTypePtr returned) {
    auto& method = *static_cast<MethodInfo*>(userdata); std::vector<V> values;
    for (size_t i = 0; i < method.arguments.size(); ++i) values.push_back(V::typed(method.arguments[i], args[i]));
    V result = invoke(method.method, values, instance);
    destruct[GDEXTENSION_VARIANT_TYPE_DICTIONARY](returned);
    to_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](returned, &result.raw);
}
}

extern "C" void ogh_math_initialize(GDExtensionInterfaceGetProcAddress api, GDExtensionClassLibraryPtr owner) {
    library = owner;
#define LOAD(name, variable) variable = reinterpret_cast<decltype(variable)>(api(name))
    LOAD("variant_new_nil", new_nil); LOAD("variant_new_copy", new_copy); LOAD("variant_destroy", destroy);
    LOAD("variant_get_type", type); LOAD("string_new_with_utf8_chars", new_string); LOAD("string_to_utf8_chars", to_utf8);
    LOAD("string_name_new_with_utf8_chars", new_name); LOAD("dictionary_operator_index", dict_index);
    LOAD("array_operator_index_const", array_index);
    LOAD("classdb_register_extension_class6", register_class); LOAD("classdb_register_extension_class_method", register_method);
    LOAD("classdb_unregister_extension_class", unregister_class);
    LOAD("classdb_construct_object3", construct_object); LOAD("object_set_instance", set_instance);
    LOAD("object_method_bind_ptrcall", object_ptrcall);
    auto get_bind = reinterpret_cast<GDExtensionInterfaceClassdbGetMethodBind>(api("classdb_get_method_bind"));
    auto get_from = reinterpret_cast<GDExtensionInterfaceGetVariantFromTypeConstructor>(api("get_variant_from_type_constructor"));
    auto get_to = reinterpret_cast<GDExtensionInterfaceGetVariantToTypeConstructor>(api("get_variant_to_type_constructor"));
    auto get_ctor = reinterpret_cast<GDExtensionInterfaceVariantGetPtrConstructor>(api("variant_get_ptr_constructor"));
    auto get_dtor = reinterpret_cast<GDExtensionInterfaceVariantGetPtrDestructor>(api("variant_get_ptr_destructor"));
    auto get_method = reinterpret_cast<GDExtensionInterfaceVariantGetPtrBuiltinMethod>(api("variant_get_ptr_builtin_method"));
    for (auto kind : {GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_BOOL, GDEXTENSION_VARIANT_TYPE_STRING_NAME, GDEXTENSION_VARIANT_TYPE_CALLABLE, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, GDEXTENSION_VARIANT_TYPE_STRING, GDEXTENSION_VARIANT_TYPE_DICTIONARY, GDEXTENSION_VARIANT_TYPE_ARRAY}) {
        from_type[kind] = get_from(kind); to_type[kind] = get_to(kind);
        construct[kind] = get_ctor(kind, 0); destruct[kind] = get_dtor(kind);
    }
    Builtin size_name, append_name, keys_name, get_name, object_name, notification_name, empty_name; Builtin hint;
    new_name(&size_name, "size"); new_name(&append_name, "append"); new_name(&keys_name, "keys");
    array_size = get_method(GDEXTENSION_VARIANT_TYPE_ARRAY, &size_name, OGH_ARRAY_SIZE_HASH);
    array_append = get_method(GDEXTENSION_VARIANT_TYPE_ARRAY, &append_name, OGH_ARRAY_APPEND_HASH);
    dictionary_keys = get_method(GDEXTENSION_VARIANT_TYPE_DICTIONARY, &keys_name, OGH_DICTIONARY_KEYS_HASH);
    new_name(&get_name, "get");
    dictionary_get = get_method(GDEXTENSION_VARIANT_TYPE_DICTIONARY, &get_name, OGH_DICTIONARY_GET_HASH);
    new_name(&math_class, "PlatformArrivalMath"); new_name(&ref_class, "RefCounted"); new_name(&empty_name, ""); new_string(&hint, "");
    new_name(&object_name, "Object"); new_name(&notification_name, "notification");
    notification = get_bind(&object_name, &notification_name, OGH_NOTIFICATION_HASH);
    GDExtensionClassCreationInfo6 info{}; info.is_exposed = 1; info.is_abstract = 1;
    register_class(owner, &math_class, &ref_class, &info);
    new_name(&model_class, "PlatformArrivalCapacity");
    GDExtensionClassCreationInfo6 model_info{}; model_info.is_exposed = 1;
    model_info.create_instance_func = create_model; model_info.free_instance_func = free_model;
    register_class(owner, &model_class, &ref_class, &model_info);
    GDExtensionPropertyInfo output{}; output.type = GDEXTENSION_VARIANT_TYPE_DICTIONARY;
    output.name = &empty_name; output.class_name = &empty_name; output.hint_string = &hint; output.usage = 6;
    for (auto& entry : methods) {
        Builtin name; new_name(&name, entry.name);
        std::vector<GDExtensionPropertyInfo> arguments(entry.arguments.size(), output);
        std::vector<Builtin> argument_names(entry.arguments.size());
        std::vector<GDExtensionClassMethodArgumentMetadata> metadata(entry.arguments.size(), GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE);
        const char* names[] = {entry.method == SOLVE_MODEL ? "budgets" : entry.method == SOLVE || entry.method == STRUCTURE || entry.method == PREPARE_MODEL ? "cases" : "operation", entry.method == STRUCTURE ? "blocked" : entry.method == SOLVE || entry.method == PREPARE_MODEL ? "budgets" : "first", entry.method == STRUCTURE ? "reception" : "second", "bed_limit"};
        for (size_t i = 0; i < arguments.size(); ++i) {
            arguments[i].type = entry.arguments[i]; new_name(&argument_names[i], names[i]); arguments[i].name = &argument_names[i];
        }
        GDExtensionClassMethodInfo method{}; method.name = &name; method.method_userdata = &entry;
        method.call_func = call; method.ptrcall_func = ptrcall;
        method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
        if (entry.method < PREPARE_MODEL) method.method_flags |= GDEXTENSION_METHOD_FLAG_STATIC;
        method.has_return_value = 1; method.return_value_info = &output;
        method.argument_count = static_cast<uint32_t>(arguments.size()); method.arguments_info = arguments.data(); method.arguments_metadata = metadata.data();
        register_method(owner, entry.method < PREPARE_MODEL ? &math_class : &model_class, &method);
        for (Builtin& argument_name : argument_names) get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&argument_name);
        get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&name);
    }
    destruct[GDEXTENSION_VARIANT_TYPE_STRING](&hint);
    spatial_register(api);
    route_queue_register(api);
    json_register(api);
    route_search_initialize(api);
    backup_zip_register(api);
    for (Builtin* name : {&size_name, &append_name, &keys_name, &get_name, &object_name, &notification_name, &empty_name}) get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(name);
#undef LOAD
}
extern "C" void ogh_math_deinitialize(GDExtensionInterfaceGetProcAddress api) {
    route_search_deinitialize(api);
    unregister_class(library, &backup_zip_class);
    route_queue_unregister(api);
    json_unregister(api);
    unregister_class(library, &spatial_class);
    unregister_class(library, &math_class);
    unregister_class(library, &model_class);
    auto get_dtor = reinterpret_cast<GDExtensionInterfaceVariantGetPtrDestructor>(api("variant_get_ptr_destructor"));
    get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&spatial_class);
    get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&backup_zip_class);
    get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&math_class);
    get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&model_class);
    get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&ref_class);
}
