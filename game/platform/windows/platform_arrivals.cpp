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

Q rational(const V& value) {
    if (type(&value.raw) == GDEXTENSION_VARIANT_TYPE_INT) return Q(std::to_string(value.number()).c_str());
    D fraction(value);
    Q result((fraction.get("n").text() + "/" + fraction.get("d").text()).c_str());
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
V structure(const V& raw_cases, const V& raw_blocked, const V& raw_reception, int64_t bed_limit) {
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
                    V raw = groups.get(V::text(group));
                    if (raw.nil()) throw std::runtime_error("结构配置缺少初诊选项");
                    A options(raw); Options unique;
                    for (int64_t j = 0; j < options.size(); ++j) unique.insert(structural_resources(D(options.at(j))));
                    auto interned = factor_ids.emplace(unique, static_cast<int>(factors.size()));
                    if (interned.second) factors.push_back(std::move(unique));
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
    result.set("terminals", V::number(static_cast<int64_t>(terminals.size()))); result.set("prefix_groups", V::number(static_cast<int64_t>(prefix_groups.size())));
    return result.value();
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
    std::map<std::string, int> shapes;
    std::vector<Case> cases;
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
    std::vector<std::pair<int, Q>> role_bounds, role_rhs;
    struct ScaledCoefficient { int row, variable; Q factor; };
    std::vector<ScaledCoefficient> role_coefficients;
    std::vector<Q> role_values;
    int64_t role_proof_reuses = 0;
    int64_t role_searches = 0;
    std::map<int, std::string> coverage_owners;
    bool coverage_owners_ready = false;

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
                Q amount = rational(values.get(key));
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
            budgets.push_back(rational(amounts.get(resource.c_str())));
        }
        A inputs(raw_cases); std::map<int, int> compact;
        for (int64_t i = 0; i < inputs.size(); ++i) {
            D input(inputs.at(i)); V raw_groups = input.get("choice_groups");
            D no_groups; D groups(raw_groups.nil() ? no_groups.value() : raw_groups);
            std::map<std::string, int> memo; std::set<std::string> visiting;
            A bundles(input.get("bundles")); Node root{true, {}, {}};
            for (int64_t j = 0; j < bundles.size(); ++j) root.children.push_back(part(bundles.at(j), groups, memo, visiting));
            int id = intern(std::move(root)); Q probability = rational(input.get("probability"));
            auto found = compact.find(id);
            if (found == compact.end()) {
                int index = static_cast<int>(cases.size()); compact[id] = index;
                cases.push_back(Case{id, 0, {}}); found = compact.find(id);
            }
            Case& target = cases[found->second]; target.probability += probability;
            target.members.push_back(Member{static_cast<int>(i), probability});
        }
        std::set<int> reachable;
        std::function<void(int)> visit = [&](int id) {
            if (!reachable.insert(id).second) return;
            for (const auto& value : nodes[id].resources) if (value.second != 0) used_resources.insert(value.first);
            for (int child : nodes[id].children) visit(child);
        };
        for (const Case& item : cases) if (item.probability > 0) visit(item.root);
        enabled.assign(nodes.size(), true);
    }
    void update_roles(const V& input) {
        D source(input); A ids(source.keys()); std::map<std::string, std::string> next;
        for (int64_t i = 0; i < ids.size(); ++i) next[ids.at(i).text()] = source.get(ids.at(i)).text();
        if (next == locked_roles) return;
        locked_roles = std::move(next); dirty = true; role_demand = 0;
        for (size_t i = 0; i < nodes.size(); ++i) {
            const Node& node = nodes[i]; bool valid = true;
            for (const auto& role : locked_roles) {
                bool own = false, active = false;
                for (const auto& term : node.resources) {
                    const auto& name = resources[term.first];
                    const std::string prefix = "coverage:" + role.first + ":";
                    if (name.compare(0, prefix.size(), prefix) == 0) {
                        if (name.substr(prefix.size()) != role.second) valid = false;
                        else own = true;
                    }
                    if (name == "staff:" + role.first) active = true;
                }
                if (active && !own) valid = false;
            }
            bool children = !node.choice;
            for (int child : node.children) {
                if (node.choice) children = children || enabled[child];
                else children = children && enabled[child];
            }
            enabled[i] = valid && children;
        }
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
        const Node& node = nodes[id];
        if (node.choice) { if (choices[id] >= 0) expand(choices[id], choices, output); }
        else {
            for (const auto& item : node.resources) output[item.first] += item.second;
            for (int child : node.children) expand(child, choices, output);
        }
    }
    V resource_values(const Resources& values) const {
        D result;
        for (const auto& item : values) if (item.second != 0) result.set(resources[item.first].c_str(), fraction(item.second));
        return result.value();
    }
    void update_budgets(const V& values) {
        D input(values);
        for (size_t i = 0; i < resources.size(); ++i) {
            Q next = rational(input.get(resources[i].c_str()));
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
        size_t edges = 0, coefficients = 0;
        for (const Node& node : nodes) { edges += node.children.size(); coefficients += node.resources.size(); }
        result.set("edge_count", V::number(edges)); result.set("coefficient_count", V::number(coefficients));
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
        auto tighten = [&](const std::vector<Q>& prices) {
            std::vector<Q> costs; std::vector<int> choices; price(prices, costs, choices);
            Q demand = 0;
            for (const Case& item : cases) demand += item.probability * costs[item.root];
            Q value = role_priced_budget(prices);
            if (demand > 0) { Q bound = value / demand; if (bound < limit) limit = bound; }
        };
        std::vector<Q> prices(resources.size(), Q(0));
        for (int resource : used_resources) prices[resource] = budgets[resource] > 0 ? Q(1) / budgets[resource] : Q(1);
        tighten(prices);
        auto bottleneck = resource_ids.find(verified_bottleneck);
        if (bottleneck != resource_ids.end()) {
            std::fill(prices.begin(), prices.end(), Q(0)); prices[bottleneck->second] = 1; tighten(prices);
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
        auto add_column = [&](int index, const Resources& values) {
            DSVectorRational column; column.add(index, Q(1));
            for (const auto& item : values) if (item.second != 0) column.add(static_cast<int>(cases.size()) + item.first, item.second);
            lp.addColRational(LPColRational(0, column, infinity, 0));
            known[index].insert(signature(values)); columns.push_back(Column{index, values});
        };
        std::vector<Q> prices(resources.size(), Q(0)), costs; std::vector<int> choices;
        if (initialize) {
            price(prices, costs, choices);
            for (size_t i = 0; i < cases.size(); ++i) { Resources values; expand(cases[i].root, choices, values); add_column(static_cast<int>(i), values); }
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
                if (known[i].count(signature(values))) throw std::runtime_error("重复资源束仍有负约化成本");
                add_column(static_cast<int>(i), values); ++added;
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
struct CapacityInstance { std::unique_ptr<Model> model; };
V aggregate_stages(const V& raw_stages, const V& raw_weight) {
    D stages(raw_stages), output, weighted, totals;
    Q weight = rational(raw_weight);
    std::map<std::string, Q> resources;
    A names(stages.keys());
    for (int64_t i = 0; i < names.size(); ++i) {
        V name = names.at(i); D stage(stages.get(name)), values;
        A ids(stage.keys());
        for (int64_t j = 0; j < ids.size(); ++j) {
            V id = ids.at(j); Q amount = rational(stage.get(id)) * weight;
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
enum Method { SOLVE, FRACTION, INTEGER, STRUCTURE, AGGREGATE, AGGREGATE_COMPONENTS, THREAD_CPU, MONOTONIC_CLOCK, PREPARE_MODEL, SOLVE_MODEL, PREPARE_ROLES, SOLVE_ROLES };
struct MethodInfo { const char* name; Method method; std::vector<GDExtensionVariantType> arguments; };
MethodInfo methods[] = {
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
            for (int64_t i = 0; i < requests.size(); ++i) {
                D request(requests.at(i));
                results.append(aggregate_stages(request.get("stages"), request.get("weight")));
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
    for (auto kind : {GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_STRING, GDEXTENSION_VARIANT_TYPE_DICTIONARY, GDEXTENSION_VARIANT_TYPE_ARRAY}) {
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
    for (Builtin* name : {&size_name, &append_name, &keys_name, &get_name, &object_name, &notification_name, &empty_name}) get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(name);
#undef LOAD
}
extern "C" void ogh_math_deinitialize(GDExtensionInterfaceGetProcAddress api) {
    unregister_class(library, &math_class);
    unregister_class(library, &model_class);
    auto get_dtor = reinterpret_cast<GDExtensionInterfaceVariantGetPtrDestructor>(api("variant_get_ptr_destructor"));
    get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&math_class);
    get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&model_class);
    get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&ref_class);
}
