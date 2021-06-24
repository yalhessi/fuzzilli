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

import Foundation
import Fuzzilli

let cacheIRProfile = Profile(
    processArguments: [
        "--no-threads",
        "--cpu-count=1",
        "--ion-offthread-compile=off",
        "--fast-warmup", // blinterp: 4 (overwritten),bljit: 10, ion: 30
        "--blinterp-eager",
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
        "FakeDOMObject" : .constructor([] => .object(ofGroup: "FakeDOMObject")),
    ]
)

var properties: [Variable: Set<String>] = [:];
var plainNatives: Set<Variable> = [];
var fancyNatives: Set<Variable> = [];
var proxies: Set<Variable> = [];
var domObjects: Set<Variable> = [];
var typedArrays: Set<Variable> = [];
var dataViews: Set<Variable> = [];
var arrayBuffers: Set<Variable> = [];
var ccws: Set<Variable> = [];
var functions: Set<Variable> = [];
var arrays: Set<Variable> = [];
var classes: Set<Variable> = [];
var classObjects: Set<Variable> = [];

func addProperty(variable vname: Variable, property pname: String) {
        if let objProps = properties[vname] {
            properties[vname]?.insert(pname)
        } else {
            properties[vname] = [pname]
         }
}

func generatePlainNative(builder b: ProgramBuilder) -> Variable {
    withEqualProbability({
        let obj = b.createObject(with: [:])
        plainNatives.insert(obj)
        return obj
    },{
        let val = b.randVar();
        let prop = withEqualProbability({
            return b.genString()
        },{
            return b.genPropertyNameForRead();
        })
        let obj = b.createObject(with: [prop: val])
        plainNatives.insert(obj)
        addProperty(variable: obj, property: prop)
        return obj
    })
}

let plainNativesGenerator = CodeGenerator("plainNativesGenerator") { b in
    generatePlainNative(builder: b)
}

let fancyNativesGenerator = CodeGenerator("fancyNativesGenerator") { b in
    let obj = generatePlainNative(builder: b)
    // TODO: add property accessors
    definePropertyGenerator.run(in: b, with: [obj])
    fancyNatives.insert(obj)
}

let proxiesGenerator = CodeGenerator("proxiesGenerator") { b in

}

let domObjectsGenerator = CodeGenerator("domObjectsGenerator") { b
    var obj = withEqualProbability({
        return b.loadBuiltin("this")
    },{
        constructBuiltin()
    })
}

func getPropertyName(inBuilder b: ProgramBuilder, forObject o: Variable) -> Variable {
    let propertyName = probability(0.5) ? b.loadString(b.genPropertyNameForWrite()) : b.loadInt(b.genIndex())
    return propertyName
}

let megamorphicICGenerator = CodeGenerator("megamorphicICGenerator") { b in
    let result: Int64 = probability(0.05) ? 1 : 0
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
                nativeSlotGetPropGenerator.run(in: b, with: [this])
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

let constructorGenerator = CodeGenerator("ConstructorCallGenerator", input: .constructor()) { b, c in
    guard let arguments = b.randCallArguments(for: c) else { return }
    b.construct(c, withArgs: arguments)
}

let typedArrayGenerator = CodeGenerator("TypedArrayGenerator") { b in
    let constructor = b.loadBuiltin(
        chooseUniform(
            from: ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray"]
        )
    )
    let interestingNats = interestingIntegers.filter {int in (0 <= int) && (int <= 2147483648)}
    let arguments = [b.loadInt(chooseUniform(from: interestingNats))]
    b.construct(constructor, withArgs: arguments)
}

let generalArrayGenerator = CodeGenerator("GeneralArrayGenerator") { b in
//there are a lot of different representations of arrays here to consider
// dense arrays --- arrays with holes
// int arrays --- float arrays --- mixed arrays
// arrays constructed using other constructors --- spread operators, anything else?
}

let ClassGenerator = CodeGenerator("ClassGenerator"){ b in 
//there is already a class generator but look into what gets generated and whether it covers the interesting cases
//does it use self. --- super.?
// can it generate setters and getters?
}

func constructBuiltin(builder b: ProgramBuilder, builtin name: String, signature: FunctionSignature? = nil) -> Variable {
    let constructor = b.loadFromScope(id: name)
    let signature = signature ?? b.fuzzer.environment.type(ofBuiltin: name).constructorSignature!
    let arguments = b.generateCallArguments(for: signature)
    return b.construct(constructor, withArgs: arguments)
}

func BuiltinGeneratorConstructor(builder b: ProgramBuilder, builtin name: String, signature: FunctionSignature? = nil) -> CodeGenerator {
    return CodeGenerator("\(name)Generator") { b in
        constructBuiltin(builder: b, builtin: name, signature: signature)
    }
}

let arrayBufferGenerator = CodeGenerator("ArrayBufferGenerator") { b in
    let constructor = b.loadFromScope(id: "ArrayBuffer")
    let interestingNats = interestingIntegers.filter {int in (0 <= int) && (int <= 2147483648)}
    let arguments = [b.loadInt(chooseUniform(from: interestingNats))]
    let obj = b.construct(constructor, withArgs: arguments)
}

func generateObject(build b: ProgramBuilder) -> Variable {
    let obj = b.createObject(with: ["a": b.loadInt(42)])
    return obj
}

let objectGenerator = CodeGenerator("CreateObject") { b in
    generateObject(build: b)
}

let stubWrapperGenerator = CodeGenerator("stubWrapperGenerator") { b in

}

func stubWrapper(do action: () -> Void) {
    // withEqualProbability({

    // })
    // if probability(prob) {
    //     action()
    // }
}

let nativeSlotGetPropGenerator = CodeGenerator("nativeSlotGetPropGenerator", input: .jsPlainObject) { b, o in
    let property = b.genPropertyNameForRead()

    withEqualProbability({
        // native_object.static_property
        b.loadProperty(property, of: o)
    },{
        // native_object[expression_property]
        // TODO: the expression here is always a string assigned right before so it can be inlined
        // we should add expressions that aren't static
        let computedProperty = b.loadString(property)
        return b.loadComputedProperty(computedProperty, of: o)
    })
}

let arrayBufferGetPropGenerator = CodeGenerator("arrayBufferGetPropGenerator", input: .jsArrayBuffer) { b, buf in
    withEqualProbability({
        b.loadProperty("byteLength", of: buf)
    }, {
        b.loadProperty("__proto__", of: buf)
    }, {
        b.loadComputedProperty(getPropertyName(inBuilder: b, forObject: buf), of: buf)
    })
}

let typedArrayGetPropGenerator = CodeGenerator("typedArrayGetPropGenerator", input: .jsTypedArray("")) { b, ta in
    withEqualProbability({
        b.loadProperty("length", of: ta)
    }, {
        b.loadProperty("byteOffset", of: ta)
    }, {
        b.loadProperty("byteLength", of: ta)
    }, {
        b.loadProperty("__proto__", of: ta)
    }, {
        b.loadComputedProperty(getPropertyName(inBuilder: b, forObject: ta), of: ta)
    })
}

let typedArrayElementGetPropGenerator = CodeGenerator("typedArrayElementGetPropGenerator", input: .jsTypedArray("")) {b, ta in

}

let getPropStubGenerator = CodeGenerator("GetPropStubGenerator") { b in
    b.run(megamorphicICGenerator)

    withEqualProbability({
        b.run(nativeSlotGetPropGenerator)
    }, {
        b.run(arrayBufferGetPropGenerator)
    }, {
        b.run(typedArrayGetPropGenerator)
    }, {

    })
    // if probability(0.5) {
    // } else if probability(0.10) {
    // } else if probability(0.10){
    // }
}

let nativeSlotSetPropGenerator = CodeGenerator("nativeSlotSetPropGenerator", input: .jsPlainObject) {b, o in
    let property = b.genPropertyNameForRead()
    let value = b.randVar()

    withEqualProbability({
        // native_object.static_property
        b.storeProperty(value, as: property, on: o)
    },{
        // native_object[expression_property]
        // TODO: the expression here is always a string assigned right before so it can be inlined
        // we should add expressions that aren't static
        let computedProperty = b.loadString(property)
        b.storeComputedProperty(value, as: computedProperty, on: o)

    },{
        b.storeElement(value, at: b.genIndex(), of: o)
    })
}

let setPropStubGenerator = CodeGenerator("SetPropStubGenerator", input: .jsPlainObject) { b, o in
    if probability(0.5) {
        nativeSlotSetPropGenerator.run(in: b, with: [o])
    } else {

    }
}

fileprivate let nativeGetPropTemplate = ProgramTemplate("nativeGetProp", requiresPrefix: false){ b in

}

let interestingIntegers: [Int64] = [-9007199254740993, -9007199254740992, -9007199254740991,          // Smallest integer value that is still precisely representable by a double
                                    -4294967297, -4294967296, -4294967295,                            // Negative Uint32 max
                                    -2147483649, -2147483648, -2147483647,                            // Int32 min
                                    -1073741824, -536870912, -268435456,                              // -2**32 / {4, 8, 16}
                                    -65537, -65536, -65535,                                           // -2**16
                                    -4096, -1024, -256, -128,                                         // Other powers of two
                                    -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 16, 64,                 // Numbers around 0
                                    127, 128, 129,                                                    // 2**7
                                    255, 256, 257,                                                    // 2**8
                                    512, 1000, 1024, 4096, 10000,                                     // Misc numbers
                                    65535, 65536, 65537,                                              // 2**16
                                    268435456, 536870912, 1073741824,                                 // 2**32 / {4, 8, 16}
                                    2147483647, 2147483648, 2147483649,                               // Int32 max
                                    4294967295, 4294967296, 4294967297,                               // Uint32 max
                                    9007199254740991, 9007199254740992, 9007199254740993,             // Biggest integer value that is still precisely representable by a double
    ]

let interestingNats = interestingIntegers.filter {int in int >= 0}


fileprivate let GetPropICTemplate = ProgramTemplate("GetPropIC", requiresPrefix: false) { b in
    // if env = b.fuzzer.environment as? JavaScriptEnvironment {
// // //                 // env.registerBuiltin("crash", ofType: .function([] => .undefined))
// // // // ?                let crash = b.loadBuiltin("crash")
// // //                 // b.callFunction(crash, withArgs: [])
// // //                 // env.removeBuiltin("crash")
    // }

    // Some additional less common object generators
    // let arrayBufferGenerator = BuiltinGeneratorConstructor(builder: b, builtin: "ArrayBuffer")
    let dataViewGenerator = BuiltinGeneratorConstructor(builder: b, builtin: "DataView")
    let mapGenerator = BuiltinGeneratorConstructor(builder: b, builtin: "Map")
    let setGenerator = BuiltinGeneratorConstructor(builder: b, builtin: "Set")
    let weakMapGenerator = BuiltinGeneratorConstructor(builder: b, builtin: "WeakMap")
    let weakSetGenerator = BuiltinGeneratorConstructor(builder: b, builtin: "WeakSet")
    let fakeDOMObjectGenerator = BuiltinGeneratorConstructor(builder: b, builtin: "FakeDOMObject")

    let defaultGenerators = b.fuzzer.codeGenerators

    let valueGenerators = WeightedList<CodeGenerator>([
        (CodeGenerators.get("IntegerGenerator"),2),
        (CodeGenerators.get("StringGenerator"),1),
        (CodeGenerators.get("FloatArrayGenerator"), 1),
        (CodeGenerators.get("IntArrayGenerator"), 1),
        (CodeGenerators.get("ArrayGenerator"), 5),
        (objectGenerator, 5),
        (arrayBufferGenerator,1),
        (typedArrayGenerator, 1),
        // (dataViewGenerator, 1),
        // (mapGenerator, 1),
        // (setGenerator, 1),
        // (weakMapGenerator, 1),
        // (weakSetGenerator, 1),
        (fakeDOMObjectGenerator, 1),
    ])

    let stubGenerators = WeightedList<CodeGenerator>([
        (getPropStubGenerator, 5),
        (setPropStubGenerator, 5),
    ])

    for generator in valueGenerators {
        b.run(generator)
    }



    // Initially Generate a bunch of objects
    // Disable splicing, as we only want the above code generators to run
    // b.fuzzer.codeGenerators = initGenerators
    // b.performSplicingDuringCodeGeneration = false
    // b.generate(n: 5)



    // generate a bunch of code, starting with a function so that an inline
    // cache is assgined to instructions inside the function
    // let funs: [Variable];
    // for _ in 1..<10 {
    let fun = b.definePlainFunction(withSignature: [] => .undefined) { params in
        // we probably want to generate some wrappers here
        // interesting ones to look at are
        // 1- for loops that trigger bl and ion ic
        // 2- try catch statements
        // 3- if statements

        b.run(getPropStubGenerator)
        b.run(setPropStubGenerator)


        //generate a get prop insturction here
        // let obj = b.randVar(ofConservativeType: .object())!
        // nativeSetPropGenerator.run(in: b, with: [obj])
    }

    // use generators to alter objects
    // b.fuzzer.codeGenerators = defaultGenerators

    // now start altering the objects we initially created
    b.generate(n: 10)

    // Enter the baseline interpreter
    b.forLoop(b.loadInt(0), .lessThan, b.loadInt(11), .Add, b.loadInt(1)) { _ in
        b.callFunction(fun, withArgs: [])
    }

    b.generate(n: 10)

    // Enter the baseline compiler
    b.forLoop(b.loadInt(0), .lessThan, b.loadInt(101), .Add, b.loadInt(1)) { _ in
        b.callFunction(fun, withArgs: [])
    }

    b.generate(n: 10)

    // Enter the warp compiler
    b.forLoop(b.loadInt(0), .lessThan, b.loadInt(101), .Add, b.loadInt(1)) { _ in
        b.callFunction(fun, withArgs: [])
    }
}

let GetPropGenerator = CodeGenerator("GetPropGenerator") { b in
    // Enumerate all of the different shapes objects take in memory
    var obj: Variable;
    var propertyKey: Variable;
    var type: Type;
    withEqualProbability({
        // native object
    })

    withEqualProbability({
    })
}

// Here instead of building templates from stubs, I build them from operation types.
// This should be much easier to get the template to cover most of the stubs, though
// this ends up being pretty coarse. Not clear if that's a bad thing yet.
fileprivate let GetPropICTemplate2 = ProgramTemplate("GetPropIC2", requiresPrefix: false) { b in
    // let arrayBufferGenerator = BuiltinGeneratorConstructor(builder: b, builtin: "ArrayBuffer")
    let dataViewGenerator = BuiltinGeneratorConstructor(builder: b, builtin: "DataView")
    let mapGenerator = BuiltinGeneratorConstructor(builder: b, builtin: "Map")
    let setGenerator = BuiltinGeneratorConstructor(builder: b, builtin: "Set")
    let weakMapGenerator = BuiltinGeneratorConstructor(builder: b, builtin: "WeakMap")
    let weakSetGenerator = BuiltinGeneratorConstructor(builder: b, builtin: "WeakSet")
    let fakeDOMObjectGenerator = BuiltinGeneratorConstructor(builder: b, builtin: "FakeDOMObject")

    let defaultGenerators = b.fuzzer.codeGenerators

    let valueGenerators = WeightedList<CodeGenerator>([
        (CodeGenerators.get("IntegerGenerator"),2),
        (CodeGenerators.get("StringGenerator"),1),
        (CodeGenerators.get("FloatArrayGenerator"), 1),
        (CodeGenerators.get("IntArrayGenerator"), 1),
        (CodeGenerators.get("ArrayGenerator"), 5),
        (objectGenerator, 5),
        (arrayBufferGenerator,1),
        (typedArrayGenerator, 1),
        // (dataViewGenerator, 1),
        // (mapGenerator, 1),
        // (setGenerator, 1),
        // (weakMapGenerator, 1),
        // (weakSetGenerator, 1),
        (fakeDOMObjectGenerator, 1),
    ])

    let stubGenerators = WeightedList<CodeGenerator>([
        (getPropStubGenerator, 5),
        (setPropStubGenerator, 5),
    ])

    for generator in valueGenerators {
        b.run(generator)
    }

    let fun = b.definePlainFunction(withSignature: [] => .undefined) { params in
        for i in 0...10 {
            let generator = stubGenerators.randomElement()
            b.run(generator)
        }
    }

    // Generate baseline and ion IC stubs
    b.forLoop(b.loadInt(0), .lessThan, b.loadInt(11), .Add, b.loadInt(1)) { _ in
        b.callFunction(fun, withArgs: [])
    }
}



//     // This template is meant to stress the v8 Map transition mechanisms.
//     // Basically, it generates a bunch of CreateObject, LoadProperty, StoreProperty, FunctionDefinition,
//     // and CallFunction operations operating on a small set of objects and property names.
//     let propertyNames = ["a", "b", "c", "d", "e", "f", "g"]

//     // Use this as base object type. For one, this ensures that the initial map is stable.
//     // Moreover, this guarantees that when querying for this type, we will receive one of
//     // the objects we created and not e.g. a function (which is also an object).
//     let objType = Type.object(withProperties: ["a"])

//     // Signature of functions generated in this template
//     let sig = [objType, objType] => objType

//     // Create property values: integers, doubles, and heap objects.
//     // These should correspond to the supported property representations of the engine.
//     let intVal = b.loadInt(42)
//     let floatVal = b.loadFloat(13.37)
//     let objVal = b.createObject(with: [:])
//     let propertyValues = [intVal, floatVal, objVal]

//     // Now create a bunch of objects to operate on.
//     // Keep track of all objects created in this template so that they can be verified at the end.
//     var objects = [objVal]
//     for _ in 0..<5 {
//         objects.append(b.createObject(with: ["a": intVal]))
//     }

//     let ForceSpidermonkeyBaselineGenerator = CodeGenerator("ForceSpidermonkeyBaselineGenerator", input: .function()) { b, f in
//     guard let arguments = b.randCallArguments(for: f) else { return }

//         let start = b.loadInt(0)
//         let end = b.loadInt(10)
//         let step = b.loadInt(1)
//         b.forLoop(start, .lessThan, end, .Add, step) { _ in
//             b.callFunction(f, withArgs: arguments)
//         }
//     }

//     let ForceSpidermonkeyIonGenerator = CodeGenerator("ForceSpidermonkeyIonGenerator", input: .function()) { b, f in
//     guard let arguments = b.randCallArguments(for: f) else { return }

//         let start = b.loadInt(0)
//         let end = b.loadInt(100)
//         let step = b.loadInt(1)
//         b.forLoop(start, .lessThan, end, .Add, step) { _ in
//             b.callFunction(f, withArgs: arguments)
//         }
//     }


//     // Next, temporarily overwrite the active code generators with the following generators...
//     let createObjectGenerator = CodeGenerator("CreateObject") { b in
//         let obj = b.createObject(with: ["a": intVal])
//         objects.append(obj)
//     }

//     let constructBuiltinGenerator = CodeGenerator("ConstructBuiltin", input: .string) { b, v in
//         let name = v.identifier
//         let constructor = b.loadFromScope(id: name)
//         let signature = b.fuzzer.environment.type(ofBuiltin: name).constructorSignature!
//         let arguments = b.generateCallArguments(for: signature)
//         let obj = b.construct(constructor, withArgs: arguments)
//     }

//     let createArrayBufferGenerator = CodeGenerator("CreateArrayBuffer") { b in
//         let constructor = b.loadFromScope(id: "ArrayBuffer")
//         let signature = b.fuzzer.environment.type(ofBuiltin: "ArrayBuffer").constructorSignature!
//         let arguments = b.generateCallArguments(for: signature)
//         let obj = b.construct(constructor, withArgs: arguments)
//     }


//     // let createArrayBufferGenerator2 = BuiltinGeneratorConstructor(builder: b, builtin: "ArrayBuffer")
//     // let createArrayBufferGenerator2 = BuiltinGeneratorConstructor(builder: b, builtin: "ArrayBuffer")
//     // let createArrayBufferGenerator2 = BuiltinGeneratorConstructor(builder: b, builtin: "ArrayBuffer")
//     // let createArrayBufferGenerator2 = BuiltinGeneratorConstructor(builder: b, builtin: "ArrayBuffer")
//     // let createArrayBufferGenerator2 = BuiltinGeneratorConstructor(builder: b, builtin: "ArrayBuffer")
//     // let createArrayBufferGenerator2 = BuiltinGeneratorConstructor(builder: b, builtin: "ArrayBuffer")



//     let propertyLoadGenerator = CodeGenerator("PropertyLoad", input: objType) { b, obj in
//         assert(objects.contains(obj))
//         b.loadProperty(chooseUniform(from: propertyNames), of: obj)
//     }
//     let propertyStoreGenerator = CodeGenerator("PropertyStore", input: objType) { b, obj in
//         assert(objects.contains(obj))
//         let numProperties = Int.random(in: 1...4)
//         for _ in 0..<numProperties {
//             b.storeProperty(chooseUniform(from: propertyValues), as: chooseUniform(from: propertyNames), on: obj)
//         }
//     }
//     let functionDefinitionGenerator = CodeGenerator("FunctionDefinition") { b in
//         let prevSize = objects.count
//         let fun = b.definePlainFunction(withSignature: sig) { params in
//             objects += params
//             b.generateRecursive()
//             b.doReturn(value: b.randVar(ofType: objType)!)
//         }
//         objects.removeLast(objects.count - prevSize)
//     }
//     let functionCallGenerator = CodeGenerator("FunctionCall", input: .function()) { b, f in
//         b.callFunction(f, withArgs: b.randCallArguments(for: f)!)
//         // // TODO: Figure out why this definition is broken

//         // let args = b.randCallArguments(for: sig)!
//         // assert(objects.contains(args[0]) && objects.contains(args[1]))
//         // let rval = b.callFunction(f, withArgs: args)
//         // assert(b.type(of: rval).Is(objType))
//         // objects.append(rval)
//     }
//     let functionJitCallGenerator = CodeGenerator("FunctionJitCall", input: .function()) { b, f in
//         let args = b.randCallArguments(for: sig)!
//         assert(objects.contains(args[0]) && objects.contains(args[1]))
//         b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { _ in
//             b.callFunction(f, withArgs: args)       // Rval goes out-of-scope immediately, so no need to track it
//         }
//     }

//     let reassignGenerator = CodeGenerator("Reassign") { b in
//         let typ = ProgramTemplate.generateType(forFuzzer: b.fuzzer);
//         let output = b.randVar(ofType: typ) ?? b.randVar();
//         let to = b.randVar(ofType: typ) ?? b.randVar();
//         // b.reassign(output, to: to)
//     }

//     let elemNameGenerator = CodeGenerator("elemName", input: .string) { b, str in
//         let newStr = b.genString()
//         b.reassign(str, to: b.loadString(newStr))
//     }


//     let prevCodeGenerators = b.fuzzer.codeGenerators
//     b.fuzzer.codeGenerators = WeightedList<CodeGenerator>([
//         // (nativeGetPropGenerator, 10),
//         // (definePropertyGenerator, 10),
//         // (megamorphicICGenerator, 1),
//         (createArrayBufferGenerator, 1),
//         (arrayBufferGenerator, 1),
//         (dataViewGenerator, 1),
//         // (mapGenerator, 1),
//         // (setGenerator, 1),
//         // (weakMapGenerator, 1),
//         // (weakSetGenerator, 1),
//         (fakeDOMObjectGenerator, 1),
//         (typedArrayGenerator, 1)
//         // (createObjectGenerator,       1),
//         // (propertyLoadGenerator,       2),
//         // (propertyStoreGenerator,      5),
//         // (functionDefinitionGenerator, 1),
//         // // (functionCallGenerator,       2),
//         // // (functionJitCallGenerator,    1)
//         // // (reassignGenerator,           3),
//         // (elemNameGenerator,           2),
//     ])

//     // Disable splicing, as we only want the above code generators to run
//     b.performSplicingDuringCodeGeneration = false

//     // ... and generate a bunch of code, starting with a function so that
//     // there is always at least one available for the call generators.
//     // b.run(functionDefinitionGenerator, recursiveCodegenBudget: 10)
//     // let funs: [Variable];
//     // for _ in 1..<10 {
//         let fun = b.definePlainFunction(withSignature: sig) { params in
//             b.generateRecursive()
//         }
//         // funs.append(fun)
//     // }
//     b.generate(n: 20)

//     // Now force compilation to use IC stubs
// //     let foo = b.loadBuiltin("foo")
//     b.forLoop(b.loadInt(0), .lessThan, b.loadInt(11), .Add, b.loadInt(1)) { _ in
//         b.callFunction(fun, withArgs: [])
//     }

//     b.generate(n: 20)

//     b.forLoop(b.loadInt(0), .lessThan, b.loadInt(101), .Add, b.loadInt(1)) { _ in
//         b.callFunction(fun, withArgs: [])
//     }

//     b.generate(n: 20)



// //     // Now, generate more code after compiling the stubs
// //     b.generate(n: 20)

// //     // // Now, restore the previous code generators, re-enable splicing, and generate some more code
// //     b.fuzzer.codeGenerators = prevCodeGenerators
// //     b.performSplicingDuringCodeGeneration = true
// //     b.generate(n: 10)



// //     // let obj = b.loadBuiltin("obj")
// //     // let foo = b.loadBuiltin("foo")

// //     // b.generate(n: 10)
    
// //     // let v = b.randVar()
// //     // b.storeProperty(v, as: "a", on: obj)

// //     // b.generate(n: 10)

// //     // b.callFunction(foo, withArgs: [])

// // //         b.performSplicingDuringCodeGeneration = false
// // //         let genSize = 10
// // //         let objGen = CodeGenerators.get("ObjectGenerator")

// // //         let v1 = b.randVar()
// // //         let v2 = b.randVar()
// // //         let v3 = b.randVar()
// // //         // let o1 = b.createObject(with: ["x" : v1, "y": v2, "z": v3])
// // //         let o1 = b.randVar(ofConservativeType: .object(ofGroup: "Object", withProperties: [], withMethods: []))
// // //         let p1 = b.genPropertyNameForRead()
// // //         b.storeProperty(v1, as: p1, on: o1 ?? v1)

// // //         let signature = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 0)
// // //         let f = b.definePlainFunction(withSignature: signature) { args in
// // //             let v2 = b.loadProperty(p1, of: o1 ?? v1)
// // //             b.doReturn(value: v2)
// // //         }

// // //         let start = b.loadInt(0)
// // //         let end = b.loadInt(10)
// // //         let step = b.loadInt(1)
// // //         b.forLoop(start, .lessThan, end, .Add, step) { _ in
// // //             b.callFunction(f, withArgs: [])
// // //         }

// // //         b.generate(n: genSize)
// // //         b.callFunction(f, withArgs: [])

// // //         let check1 = b.compare(b.callFunction(f, withArgs: []), b.loadProperty(p1, of: o1 ?? v1), with: .notEqual)
// // //         b.beginIf(check1) {
// // //             b.eval("fuzzilli('FUZZILLI_CRASH', 0)")
// // //             // if let env = b.fuzzer.environment as? JavaScriptEnvironment {
// // //                 // env.registerBuiltin("crash", ofType: .function([] => .undefined))
// // // // ?                let crash = b.loadBuiltin("crash")
// // //                 // b.callFunction(crash, withArgs: [])
// // //                 // env.removeBuiltin("crash")
// // //             // }
// // //         }
// // //         b.endIf();

// // //         let start2 = b.loadInt(0)
// // //         let end2 = b.loadInt(100)
// // //         let step2 = b.loadInt(1)
// // //         b.forLoop(start2, .lessThan, end2, .Add, step2) { _ in
// // //             b.callFunction(f, withArgs: [])
// // //         }

// // //         b.generate(n: genSize)
// // //         b.callFunction(f, withArgs: [])
        
// // //         let check2 = b.compare(b.callFunction(f, withArgs: []), b.loadProperty(p1, of: o1 ?? v1), with: .notEqual)
// // //         b.beginIf(check2) {
// // //             b.eval("fuzzilli('FUZZILLI_CRASH', 0)")
// // //             // if let env = b.fuzzer.environment as? JavaScriptEnvironment {
// // //                 // env.registerBuiltin("crash", ofType: .function([] => .undefined))
// // // // ?                let crash = b.loadBuiltin("crash")
// // //                 // b.callFunction(crash, withArgs: [])
// // //                 // env.removeBuiltin("crash")
// // //             // }
// // //         }
// // //         b.endIf();
// //         // b.throwException(check)

// //         // let v1 = b.createObject(with: [:])
// //         // let v2 = b.create
// //         // b.storeProperty(value: , as: "x", on: v1)
// //         // let p1 = b.randVar()
// //         // let p2 = b.randVar()
// //         // let v1 = b.createObject(with: ["x" : p1, "y": p2])

// //         // let signature = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 0)
// //         // let f = b.definePlainFunction(withSignature: signature) { args in
// //         //     let v2 = b.loadProperty("x", of: v1 ?? v2)
// //         //     b.doReturn(value: v2)
// //         // }


// //         // b.run(ForceSpidermonkeyBaselineGenerator)
// //         // b.generate(n: genSize)
// //         // b.callFunction(f, withArgs: [])

// //         // Generate random function signatures as our helpers
// //         // var functionSignatures = ProgramTemplate.generateRandomFunctionSignatures(forFuzzer: b.fuzzer, n: 2)

// //         // Generate random property types
// //         // ProgramTemplate.generateRandomPropertyTypes(forBuilder: b)

// //         // // Generate random method types
// //         // ProgramTemplate.generateRandomMethodTypes(forBuilder: b, n: 2)

// //         // b.generate(n: genSize)

// //         // // Generate some small functions
// //         // for signature in functionSignatures {
// //         //     // Here generate a random function type, e.g. arrow/generator etc
// //         //     b.definePlainFunction(withSignature: signature) { args in
// //         //         b.generate(n: genSize)
// //         //     }
// //         // }

// //         // // Generate a larger function
// //         // let signature = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 4)
// //         // let f = b.definePlainFunction(withSignature: signature) { args in
// //         //     // Generate (larger) function body
// //         //     b.generate(n: 30)
// //         // }

// //         // // Generate some random instructions now
// //         // b.generate(n: genSize)

// //         // // trigger JIT
// //         // b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
// //         //     b.callFunction(f, withArgs: b.generateCallArguments(for: signature))
// //         // }

// //         // // more random instructions
// //         // b.generate(n: genSize)
// //         // b.callFunction(f, withArgs: b.generateCallArguments(for: signature))

// //         // // maybe trigger recompilation
// //         // b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
// //         //     b.callFunction(f, withArgs: b.generateCallArguments(for: signature))
// //         // }

// //         // // more random instructions
// //         // b.generate(n: genSize)

// //         // b.callFunction(f, withArgs: b.generateCallArguments(for: signature))