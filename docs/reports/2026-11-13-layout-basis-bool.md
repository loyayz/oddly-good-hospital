# Landing layout-basis comparison reuse

Retained as a small local equivalence refactor under the user's policy of keeping local work reductions without a large overall performance decline. This is NOT a demonstrated whole-game acceleration or a CPU-target pass.

Base: 796191e6d7ad12e74772e9c8ee7b3c5312361740. The only production change preserves the boarding-call lookup first, computes layout_basis equality once, and reuses that Boolean in the same unchanged-input window. No cross-tick cache, business timing, collision, workload, or acceptance threshold changes.

## Local correctness and cost
Independent review confirms the intervening erase operations cannot mutate either comparison input. Eight explicitly synthetic branch/erase tests passed; they do not execute slot geometry. Real snapshot and SPACE54/SPACE55 group subfixtures observed equal-basis branches, retaining the live array references and guarding against mutation before timing. Local branch-fragment medians were 1.1145 -> 0.7175 microseconds without a boarding call, and 0.523 -> 0.534 with a boarding call. These are not full-sync or whole-game savings. Bounded samples are not uniformly drawn from all inputs.

Actual different-basis branches remain unobserved. An extra real FIFO fixture did not reach simultaneous registration; its failed prerequisite is retained, not called a regression or passed coverage. The synthetic tests and local semantic proof supplement but do not erase this scope limit.

## Complete input comparison
Three candidate rounds and three prior controls use the same full 160-person initial scenario, 1000 prefix + 6000 measured steps, unchanged comprehensive actions and thresholds. Every round passes coverage and exact final World/RNG/ordered events:
8baf906509e5d0bfd5266adcfe5a3455fb274cc3aae00e786a6996b46d15dbbb.
All three candidate raw rounds were independently persisted and actually read back member-by-member.

The same dense window contains 5439 samples. Control -> candidate medians:
- P95:119.582 ->122.435 ms (+2.39%).
- P99:146.968 ->152.812 ms (+3.98%).
- Maximum:452.094 ->464.275 ms (+2.69%).
- Sum of the 6000 measured Simulation.step spans:375.928814 ->383.523518 seconds (+2.02%); excludes prefix.

Thus the measured whole workload is modestly slower, not faster. The user-approved retention judgment treats this as not a large decline and values the simple local reduction; it is not a causal claim or proof of no regression. Runs were not interleaved, and historical unguarded/failed process terminal states remain uncertain despite the cooperative lock used for these rounds. Environment effects cannot be excluded. Absolute CPU targets remain unmet. See the companion JSON for individual rounds.

The retained synthetic runner accepts an output JSON path and explicitly labels its scope; it is not full actual-branch acceptance.
