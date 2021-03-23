// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Fuzzilli

fileprivate let ForceSpidermonkeyBaselineGenerator = CodeGenerator("ForceSpidermonkeyBaselineGenerator", input: .function()) { b, f in
   guard let arguments = b.randCallArguments(for: f) else { return }
    
    let start = b.loadInt(0)
    let end = b.loadInt(10)
    let step = b.loadInt(1)
    b.forLoop(start, .lessThan, end, .Add, step) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

fileprivate let ForceSpidermonkeyIonGenerator = CodeGenerator("ForceSpidermonkeyIonGenerator", input: .function()) { b, f in
   guard let arguments = b.randCallArguments(for: f) else { return }
    
    let start = b.loadInt(0)
    let end = b.loadInt(100)
    let step = b.loadInt(1)
    b.forLoop(start, .lessThan, end, .Add, step) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

let spidermonkeyProfile = Profile(
    processArguments: [
        "--no-threads",
        "--cpu-count=1",
        "--ion-offthread-compile=off",
        "--baseline-warmup-threshold=10",
        "--ion-warmup-threshold=100",
        "--ion-check-range-analysis",
        "--ion-extra-checks",
        "--fuzzing-safe",
        "--reprl",
    ],
// let spidermonkeyProfile = Profile(
//     processArguments: [
//         "--no-threads",
//         "--cpu-count=1",
//         "--ion-offthread-compile=off",
//         "--blinterp-eager",
//         "--ion-warmup-threshold=100",
//         "--ion-check-range-analysis",
//         "--ion-extra-checks",
//         "--fuzzing-safe",
//         "--reprl",
//     ],

    processEnv: ["UBSAN_OPTIONS": "handle_segv=0"],

    codePrefix: "",

    codeSuffix: "gc();",

    ecmaVersion: ECMAScriptVersion.es6,

    crashTests: ["fuzzilli('FUZZILLI_CRASH', 0)", "fuzzilli('FUZZILLI_CRASH', 1)", "fuzzilli('FUZZILLI_CRASH', 2)"],

    additionalCodeGenerators: WeightedList<CodeGenerator>([
        (ForceSpidermonkeyIonGenerator, 10),
    ]),

    additionalProgramTemplates: WeightedList<ProgramTemplate>([(GetPropICTemplate, 100)]),

    disabledCodeGenerators: [],

    additionalBuiltins: [
        "gc"            : .function([] => .undefined),
        "enqueueJob"    : .function([.function()] => .undefined),
        "drainJobQueue" : .function([] => .undefined),
        "bailout"       : .function([] => .undefined),
    ]
)


fileprivate let GetPropICTemplate = ProgramTemplate("GetPropIC", requiresPrefix: true) { b in
        b.performSplicingDuringCodeGeneration = false
        let genSize = 10
        let objGen = CodeGenerators.get("ObjectGenerator")

        let v1 = b.randVar()
        let v2 = b.randVar()
        let v3 = b.randVar()
        // let o1 = b.createObject(with: ["x" : v1, "y": v2, "z": v3])
        let o1 = b.randVar(ofConservativeType: .object(ofGroup: "Object", withProperties: [], withMethods: []))
        let p1 = b.genPropertyNameForRead()
        b.storeProperty(v1, as: p1, on: o1 ?? v1)

        let signature = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 0)
        let f = b.definePlainFunction(withSignature: signature) { args in
            let v2 = b.loadProperty(p1, of: o1 ?? v1)
            b.doReturn(value: v2)
        }

        let start = b.loadInt(0)
        let end = b.loadInt(10)
        let step = b.loadInt(1)
        b.forLoop(start, .lessThan, end, .Add, step) { _ in
            b.callFunction(f, withArgs: [])
        }

        b.generate(n: genSize)
        b.callFunction(f, withArgs: [])

        let check1 = b.compare(b.callFunction(f, withArgs: []), b.loadProperty(p1, of: o1 ?? v1), with: .notEqual)
        b.beginIf(check1) {
            b.eval("fuzzilli('FUZZILLI_CRASH', 0)")
            // if let env = b.fuzzer.environment as? JavaScriptEnvironment {
                // env.registerBuiltin("crash", ofType: .function([] => .undefined))
// ?                let crash = b.loadBuiltin("crash")
                // b.callFunction(crash, withArgs: [])
                // env.removeBuiltin("crash")
            // }
        }
        b.endIf();

        let start2 = b.loadInt(0)
        let end2 = b.loadInt(100)
        let step2 = b.loadInt(1)
        b.forLoop(start2, .lessThan, end2, .Add, step2) { _ in
            b.callFunction(f, withArgs: [])
        }

        b.generate(n: genSize)
        b.callFunction(f, withArgs: [])
        
        let check2 = b.compare(b.callFunction(f, withArgs: []), b.loadProperty(p1, of: o1 ?? v1), with: .notEqual)
        b.beginIf(check2) {
            b.eval("fuzzilli('FUZZILLI_CRASH', 0)")
            // if let env = b.fuzzer.environment as? JavaScriptEnvironment {
                // env.registerBuiltin("crash", ofType: .function([] => .undefined))
// ?                let crash = b.loadBuiltin("crash")
                // b.callFunction(crash, withArgs: [])
                // env.removeBuiltin("crash")
            // }
        }
        b.endIf();
        // b.throwException(check)

        // let v1 = b.createObject(with: [:])
        // let v2 = b.create
        // b.storeProperty(value: , as: "x", on: v1)
        // let p1 = b.randVar()
        // let p2 = b.randVar()
        // let v1 = b.createObject(with: ["x" : p1, "y": p2])

        // let signature = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 0)
        // let f = b.definePlainFunction(withSignature: signature) { args in
        //     let v2 = b.loadProperty("x", of: v1 ?? v2)
        //     b.doReturn(value: v2)
        // }


        // b.run(ForceSpidermonkeyBaselineGenerator)
        // b.generate(n: genSize)
        // b.callFunction(f, withArgs: [])

        // Generate random function signatures as our helpers
        // var functionSignatures = ProgramTemplate.generateRandomFunctionSignatures(forFuzzer: b.fuzzer, n: 2)

        // Generate random property types
        // ProgramTemplate.generateRandomPropertyTypes(forBuilder: b)

        // // Generate random method types
        // ProgramTemplate.generateRandomMethodTypes(forBuilder: b, n: 2)

        // b.generate(n: genSize)

        // // Generate some small functions
        // for signature in functionSignatures {
        //     // Here generate a random function type, e.g. arrow/generator etc
        //     b.definePlainFunction(withSignature: signature) { args in
        //         b.generate(n: genSize)
        //     }
        // }

        // // Generate a larger function
        // let signature = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 4)
        // let f = b.definePlainFunction(withSignature: signature) { args in
        //     // Generate (larger) function body
        //     b.generate(n: 30)
        // }

        // // Generate some random instructions now
        // b.generate(n: genSize)

        // // trigger JIT
        // b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
        //     b.callFunction(f, withArgs: b.generateCallArguments(for: signature))
        // }

        // // more random instructions
        // b.generate(n: genSize)
        // b.callFunction(f, withArgs: b.generateCallArguments(for: signature))

        // // maybe trigger recompilation
        // b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
        //     b.callFunction(f, withArgs: b.generateCallArguments(for: signature))
        // }

        // // more random instructions
        // b.generate(n: genSize)

        // b.callFunction(f, withArgs: b.generateCallArguments(for: signature))    
    }
