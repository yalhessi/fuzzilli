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

let cacheIRProfile = Profile(
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

    processEnv: ["UBSAN_OPTIONS": "handle_segv=0"],

    codePrefix: """
    """,

    codeSuffix: """
    gc();
    """,

    ecmaVersion: ECMAScriptVersion.es6,

    crashTests: ["fuzzilli('FUZZILLI_CRASH', 0)", "fuzzilli('FUZZILLI_CRASH', 1)", "fuzzilli('FUZZILLI_CRASH', 2)"],

    additionalCodeGenerators: WeightedList<CodeGenerator>([]),

    additionalProgramTemplates: WeightedList<ProgramTemplate>([(GetPropICTemplate, 100)]),

    disabledCodeGenerators: [],

    additionalBuiltins: [
        "gc"            : .function([] => .undefined),
        "enqueueJob"    : .function([.function()] => .undefined),
        "drainJobQueue" : .function([] => .undefined),
        "bailout"       : .function([] => .undefined),
        "setJitCompilerOption": .function([.string, .number] => .undefined),
        "FakeDOMObject" : .constructor(),
    ]
)

func getPropertyName(inBuilder b: ProgramBuilder, forObject o: Variable) -> Variable { 
    let propertyName = probability(0.5) ? b.loadString(b.genPropertyNameForWrite()) : b.loadInt(b.genIndex())
    return propertyName
}

let megamorphicICGenerator = CodeGenerator("megamorphicICGenerator") { b in
    let result: Int64 = probability(0.1) ? 1 : 0
    let options = b.loadBuiltin("setJitCompilerOption")
    b.callFunction(options, withArgs: [b.loadString("ic.force-megamorphic"), b.loadInt(result)])
}

let definePropertyGenerator = CodeGenerator("definePropertyGenerator", input: .jsPlainObject) { b, o in
    let propertyName = getPropertyName(inBuilder: b, forObject: o)
    
    var initialProperties = [String: Variable]()
    initialProperties["configurable"] = b.loadBool(true)
    withEqualProbability({
        withEqualProbability({
            guard let getter = b.randVar(ofType: .function()) else { return }
            initialProperties["get"] = getter            
        },{
            let getter = b.defineArrowFunction(withSignature: [] => .anything) { params in
                let this = b.loadFromScope(id: "this")
                nativeGetPropGenerator.run(in: b, with: [this])
            }
            initialProperties["get"] = getter
        })
    // }, {
    //     guard let setter = b.randVar(ofType: .function()) else { return }
    //     initialProperties["set"] = setter
    // }, {
    //     guard let getter = b.randVar(ofType: .function()) else { return }
    //     guard let setter = b.randVar(ofType: .function()) else { return }
    //     initialProperties["get"] = getter
    //     initialProperties["set"] = setter
    })
    let descriptor = b.createObject(with: initialProperties)
    
    let object = b.loadBuiltin("Object")
    b.callMethod("defineProperty", on: object, withArgs: [o, propertyName, descriptor])
}

let domObjectGenerator = CodeGenerator("domObjectGenerator") { b in 
    let constructor = b.loadFromScope(id: "FakeDOMObject")
    b.construct(constructor, withArgs: [])
}

let nativeGetPropGenerator = CodeGenerator("nativeGetProp", input: .jsPlainObject) { b, o in 
    let property = b.genPropertyNameForRead()
    if (probability(0.5)) {
        // native_object.static_property
        b.loadProperty(property, of: o)
    } else {
        // native_object[expression_property]
        // TODO: the expression here is always a string assigned right before so it can be inlined
        // we should add expressions that aren't static
        let computerProperty = b.loadString(property)
        b.loadComputedProperty(computerProperty, of: o)
        
    }
}

// let selectPropGenerator = CodeGenerator("selectProp", input: .object()) { b, o in 
//     b.genPropertyNameForRead()
// }


fileprivate let GetPropICTemplate = ProgramTemplate("GetPropIC", requiresPrefix: false) { b in
    // let sig = [] => .undefined
    // let f = b.definePlainFunction(withSignature: sig) { params in
    //     b.generate(n: 10);
    // }
    // b.storeToScope(f, as: "foo")

    // This template is meant to stress the v8 Map transition mechanisms.
    // Basically, it generates a bunch of CreateObject, LoadProperty, StoreProperty, FunctionDefinition,
    // and CallFunction operations operating on a small set of objects and property names.
    let propertyNames = ["a", "b", "c", "d", "e", "f", "g"]

    // Use this as base object type. For one, this ensures that the initial map is stable.
    // Moreover, this guarantees that when querying for this type, we will receive one of
    // the objects we created and not e.g. a function (which is also an object).
    let objType = Type.object(withProperties: ["a"])

    // Signature of functions generated in this template
    let sig = [objType, objType] => objType

    // Create property values: integers, doubles, and heap objects.
    // These should correspond to the supported property representations of the engine.
    let intVal = b.loadInt(42)
    let floatVal = b.loadFloat(13.37)
    let objVal = b.createObject(with: [:])
    let propertyValues = [intVal, floatVal, objVal]

    // Now create a bunch of objects to operate on.
    // Keep track of all objects created in this template so that they can be verified at the end.
    var objects = [objVal]
    for _ in 0..<5 {
        objects.append(b.createObject(with: ["a": intVal]))
    }

    let ForceSpidermonkeyBaselineGenerator = CodeGenerator("ForceSpidermonkeyBaselineGenerator", input: .function()) { b, f in
    guard let arguments = b.randCallArguments(for: f) else { return }
        
        let start = b.loadInt(0)
        let end = b.loadInt(10)
        let step = b.loadInt(1)
        b.forLoop(start, .lessThan, end, .Add, step) { _ in
            b.callFunction(f, withArgs: arguments)
        }
    }

    let ForceSpidermonkeyIonGenerator = CodeGenerator("ForceSpidermonkeyIonGenerator", input: .function()) { b, f in
    guard let arguments = b.randCallArguments(for: f) else { return }
        
        let start = b.loadInt(0)
        let end = b.loadInt(100)
        let step = b.loadInt(1)
        b.forLoop(start, .lessThan, end, .Add, step) { _ in
            b.callFunction(f, withArgs: arguments)
        }
    }


    // Next, temporarily overwrite the active code generators with the following generators...
    let createObjectGenerator = CodeGenerator("CreateObject") { b in
        let obj = b.createObject(with: ["a": intVal])
        objects.append(obj)
    }
    let propertyLoadGenerator = CodeGenerator("PropertyLoad", input: objType) { b, obj in
        assert(objects.contains(obj))
        b.loadProperty(chooseUniform(from: propertyNames), of: obj)
    }
    let propertyStoreGenerator = CodeGenerator("PropertyStore", input: objType) { b, obj in
        assert(objects.contains(obj))
        let numProperties = Int.random(in: 1...4)
        for _ in 0..<numProperties {
            b.storeProperty(chooseUniform(from: propertyValues), as: chooseUniform(from: propertyNames), on: obj)
        }
    }
    let functionDefinitionGenerator = CodeGenerator("FunctionDefinition") { b in
        let prevSize = objects.count
        let fun = b.definePlainFunction(withSignature: sig) { params in
            objects += params
            b.generateRecursive()
            b.doReturn(value: b.randVar(ofType: objType)!)
        }
        objects.removeLast(objects.count - prevSize)
    }
    let functionCallGenerator = CodeGenerator("FunctionCall", input: .function()) { b, f in
        b.callFunction(f, withArgs: b.randCallArguments(for: f)!)
        // // TODO: Figure out why this definition is broken
    
        // let args = b.randCallArguments(for: sig)!
        // assert(objects.contains(args[0]) && objects.contains(args[1]))
        // let rval = b.callFunction(f, withArgs: args)
        // assert(b.type(of: rval).Is(objType))
        // objects.append(rval)
    }
    let functionJitCallGenerator = CodeGenerator("FunctionJitCall", input: .function()) { b, f in
        let args = b.randCallArguments(for: sig)!
        assert(objects.contains(args[0]) && objects.contains(args[1]))
        b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { _ in
            b.callFunction(f, withArgs: args)       // Rval goes out-of-scope immediately, so no need to track it
        }
    }

    let reassignGenerator = CodeGenerator("Reassign") { b in
        let typ = ProgramTemplate.generateType(forFuzzer: b.fuzzer); 
        let output = b.randVar(ofType: typ) ?? b.randVar();
        let to = b.randVar(ofType: typ) ?? b.randVar();
        // b.reassign(output, to: to)
    }

    let elemNameGenerator = CodeGenerator("elemName", input: .string) { b, str in
        let newStr = b.genString()
        b.reassign(str, to: b.loadString(newStr))
    }


    let prevCodeGenerators = b.fuzzer.codeGenerators
    b.fuzzer.codeGenerators = WeightedList<CodeGenerator>([
        (nativeGetPropGenerator, 10),
        (definePropertyGenerator, 10),
        (domObjectGenerator, 1),
        (megamorphicICGenerator, 1),
        // (createObjectGenerator,       1),
        // (propertyLoadGenerator,       2),
        // (propertyStoreGenerator,      5),
        // (functionDefinitionGenerator, 1),
        // // (functionCallGenerator,       2),
        // // (functionJitCallGenerator,    1)
        // // (reassignGenerator,           3),
        // (elemNameGenerator,           2),
    ])

    // Disable splicing, as we only want the above code generators to run
    b.performSplicingDuringCodeGeneration = false

    // ... and generate a bunch of code, starting with a function so that
    // there is always at least one available for the call generators.
    // b.run(functionDefinitionGenerator, recursiveCodegenBudget: 10)
    // let funs: [Variable];
    // for _ in 1..<10 {
        let fun = b.definePlainFunction(withSignature: sig) { params in
            b.generateRecursive()
        }
        // funs.append(fun)
    // }
    b.generate(n: 20)

    // Now force compilation to use IC stubs
//     let foo = b.loadBuiltin("foo")
    b.forLoop(b.loadInt(0), .lessThan, b.loadInt(11), .Add, b.loadInt(1)) { _ in
        b.callFunction(fun, withArgs: [])
    }

    b.generate(n: 20)

    b.forLoop(b.loadInt(0), .lessThan, b.loadInt(101), .Add, b.loadInt(1)) { _ in
        b.callFunction(fun, withArgs: [])
    }

    b.generate(n: 20)



//     // Now, generate more code after compiling the stubs
//     b.generate(n: 20)

//     // // Now, restore the previous code generators, re-enable splicing, and generate some more code
//     b.fuzzer.codeGenerators = prevCodeGenerators
//     b.performSplicingDuringCodeGeneration = true
//     b.generate(n: 10)



//     // let obj = b.loadBuiltin("obj")
//     // let foo = b.loadBuiltin("foo")

//     // b.generate(n: 10)
    
//     // let v = b.randVar()
//     // b.storeProperty(v, as: "a", on: obj)

//     // b.generate(n: 10)

//     // b.callFunction(foo, withArgs: [])

// //         b.performSplicingDuringCodeGeneration = false
// //         let genSize = 10
// //         let objGen = CodeGenerators.get("ObjectGenerator")

// //         let v1 = b.randVar()
// //         let v2 = b.randVar()
// //         let v3 = b.randVar()
// //         // let o1 = b.createObject(with: ["x" : v1, "y": v2, "z": v3])
// //         let o1 = b.randVar(ofConservativeType: .object(ofGroup: "Object", withProperties: [], withMethods: []))
// //         let p1 = b.genPropertyNameForRead()
// //         b.storeProperty(v1, as: p1, on: o1 ?? v1)

// //         let signature = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 0)
// //         let f = b.definePlainFunction(withSignature: signature) { args in
// //             let v2 = b.loadProperty(p1, of: o1 ?? v1)
// //             b.doReturn(value: v2)
// //         }

// //         let start = b.loadInt(0)
// //         let end = b.loadInt(10)
// //         let step = b.loadInt(1)
// //         b.forLoop(start, .lessThan, end, .Add, step) { _ in
// //             b.callFunction(f, withArgs: [])
// //         }

// //         b.generate(n: genSize)
// //         b.callFunction(f, withArgs: [])

// //         let check1 = b.compare(b.callFunction(f, withArgs: []), b.loadProperty(p1, of: o1 ?? v1), with: .notEqual)
// //         b.beginIf(check1) {
// //             b.eval("fuzzilli('FUZZILLI_CRASH', 0)")
// //             // if let env = b.fuzzer.environment as? JavaScriptEnvironment {
// //                 // env.registerBuiltin("crash", ofType: .function([] => .undefined))
// // // ?                let crash = b.loadBuiltin("crash")
// //                 // b.callFunction(crash, withArgs: [])
// //                 // env.removeBuiltin("crash")
// //             // }
// //         }
// //         b.endIf();

// //         let start2 = b.loadInt(0)
// //         let end2 = b.loadInt(100)
// //         let step2 = b.loadInt(1)
// //         b.forLoop(start2, .lessThan, end2, .Add, step2) { _ in
// //             b.callFunction(f, withArgs: [])
// //         }

// //         b.generate(n: genSize)
// //         b.callFunction(f, withArgs: [])
        
// //         let check2 = b.compare(b.callFunction(f, withArgs: []), b.loadProperty(p1, of: o1 ?? v1), with: .notEqual)
// //         b.beginIf(check2) {
// //             b.eval("fuzzilli('FUZZILLI_CRASH', 0)")
// //             // if let env = b.fuzzer.environment as? JavaScriptEnvironment {
// //                 // env.registerBuiltin("crash", ofType: .function([] => .undefined))
// // // ?                let crash = b.loadBuiltin("crash")
// //                 // b.callFunction(crash, withArgs: [])
// //                 // env.removeBuiltin("crash")
// //             // }
// //         }
// //         b.endIf();
//         // b.throwException(check)

//         // let v1 = b.createObject(with: [:])
//         // let v2 = b.create
//         // b.storeProperty(value: , as: "x", on: v1)
//         // let p1 = b.randVar()
//         // let p2 = b.randVar()
//         // let v1 = b.createObject(with: ["x" : p1, "y": p2])

//         // let signature = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 0)
//         // let f = b.definePlainFunction(withSignature: signature) { args in
//         //     let v2 = b.loadProperty("x", of: v1 ?? v2)
//         //     b.doReturn(value: v2)
//         // }


//         // b.run(ForceSpidermonkeyBaselineGenerator)
//         // b.generate(n: genSize)
//         // b.callFunction(f, withArgs: [])

//         // Generate random function signatures as our helpers
//         // var functionSignatures = ProgramTemplate.generateRandomFunctionSignatures(forFuzzer: b.fuzzer, n: 2)

//         // Generate random property types
//         // ProgramTemplate.generateRandomPropertyTypes(forBuilder: b)

//         // // Generate random method types
//         // ProgramTemplate.generateRandomMethodTypes(forBuilder: b, n: 2)

//         // b.generate(n: genSize)

//         // // Generate some small functions
//         // for signature in functionSignatures {
//         //     // Here generate a random function type, e.g. arrow/generator etc
//         //     b.definePlainFunction(withSignature: signature) { args in
//         //         b.generate(n: genSize)
//         //     }
//         // }

//         // // Generate a larger function
//         // let signature = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 4)
//         // let f = b.definePlainFunction(withSignature: signature) { args in
//         //     // Generate (larger) function body
//         //     b.generate(n: 30)
//         // }

//         // // Generate some random instructions now
//         // b.generate(n: genSize)

//         // // trigger JIT
//         // b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
//         //     b.callFunction(f, withArgs: b.generateCallArguments(for: signature))
//         // }

//         // // more random instructions
//         // b.generate(n: genSize)
//         // b.callFunction(f, withArgs: b.generateCallArguments(for: signature))

//         // // maybe trigger recompilation
//         // b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
//         //     b.callFunction(f, withArgs: b.generateCallArguments(for: signature))
//         // }

//         // // more random instructions
//         // b.generate(n: genSize)

//         // b.callFunction(f, withArgs: b.generateCallArguments(for: signature))    
    }