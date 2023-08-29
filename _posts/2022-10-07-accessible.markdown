---
layout: post
title:  "2019 强网杯 accessible分析"
date:   2023-08-29 07:20:22 +0800
categories: v8
---
# 2019 qwb accessible

## 分析patch

```diff
diff --git a/src/compiler/access-info.cc b/src/compiler/access-info.cc
index 0744138..1df06df 100644
--- a/src/compiler/access-info.cc
+++ b/src/compiler/access-info.cc
@@ -370,9 +370,11 @@ PropertyAccessInfo AccessInfoFactory::ComputeDataFieldAccessInfo(
       // The field type was cleared by the GC, so we don't know anything
       // about the contents now.
     }
+#if 0
     unrecorded_dependencies.push_back(
         dependencies()->FieldRepresentationDependencyOffTheRecord(map_ref,
                                                                   descriptor));
+#endif
     if (descriptors_field_type->IsClass()) {
       // Remember the field map, and try to infer a useful type.
       Handle<Map> map(descriptors_field_type->AsClass(), isolate());
@@ -384,15 +386,17 @@ PropertyAccessInfo AccessInfoFactory::ComputeDataFieldAccessInfo(
   }
   // TODO(turbofan): We may want to do this only depending on the use
   // of the access info.
+#if 0
   unrecorded_dependencies.push_back(
       dependencies()->FieldTypeDependencyOffTheRecord(map_ref, descriptor));
+#endif
 
   PropertyConstness constness;
   if (details.IsReadOnly() && !details.IsConfigurable()) {
     constness = PropertyConstness::kConst;
   } else {
     map_ref.SerializeOwnDescriptor(descriptor);
-    constness = dependencies()->DependOnFieldConstness(map_ref, descriptor);
+    constness = PropertyConstness::kConst;
   }
   Handle<Map> field_owner_map(map->FindFieldOwner(isolate(), descriptor),
                               isolate());
```

patch点位于ComputeDataFieldAccessInfo中

将两个unrecord_dependencies.push的操作注释掉了，同时将PropertyConstness类型的constness将原来的DependOnFieldConstness结果改为了固定的kConst

找到该函数的源码

![image-20230602161311034](imgs/image-20230602161311034.png)

该函数返回了一个DataField或者DataConst，但是仅有一个kind不同

![image-20230602161617639](imgs/image-20230602161617639.png)

同时也注意到第一个push出现在details_representation为HeapObject的case

![image-20230602161358730](imgs/image-20230602161358730.png)

向上查看details_representation指代的对象是谁

![image-20230602161733603](imgs/image-20230602161733603.png)

从details获取details_representation，details为map的DescriptorArray中的某一项属性记录的detail

receiver_map为被查找对象的map，向上寻找map变量的来源

![image-20230603200121221](imgs/image-20230603200121221.png)

经过一些调试会发现此时的receiver_map与map均为被访问对象的map

此循环在原型链上搜索属性，以map为循环变量，传入的map为实际的拥有属性的对象的map，所以如果仅在变量上定义属性时这里一般会相等

分析一下被去掉的代码的作用

![image-20230603201225324](imgs/image-20230603201225324.png)

![image-20230603201236889](imgs/image-20230603201236889.png)

函数产生了一个CompilationDependency一个抽象基类指针

CompilationDependency派生出很多Dependency

![image-20230603201449118](imgs/image-20230603201449118.png)

![image-20230603201523083](imgs/image-20230603201523083.png)

都实现了Install函数，对code安装依赖

根据对jit编译的了解，可以知道这些dependency是用来标明jit代码的依赖，当依赖不满足时及时地将代码deoptimize回bytecode解释器执行

![image-20230603201853383](imgs/image-20230603201853383.png)

在建立依赖的过程中，首先从拥有属性的map中调用FindFieldOwner

需要理解一下这个fieldowner具体是指谁的map

![image-20230606144603524](imgs/image-20230606144603524.png)

实现中有两种实现，在jsheapbroker的模式为disable时调用map的FindFieldOwner方法

或者是从mapref类所引用的map的instance_descriptors中找到对应索引的PropertyDescriptor

![image-20230606144808193](imgs/image-20230606144808193.png)

里面只有一个字段看起来是与map相关的，即field_owner

我们写一个例子来看一下

```js
var o = {'p':{'q':1.1}};
%DebugPrint(o);
%DebugPrint(o.p);
%SystemBreak();
```

```
DebugPrint: 0x273fe544b249: [JS_OBJECT_TYPE]
 - map: 0x11232970a6b9 <Map(HOLEY_ELEMENTS)> [FastProperties]
 - prototype: 0x1b89284c20e1 <Object map = 0x112329700209>
 - elements: 0x1cf27a1c0c01 <FixedArray[0]> [HOLEY_ELEMENTS]
 - properties: 0x1cf27a1c0c01 <FixedArray[0]> {
    #p: 0x273fe544b269 <Object map = 0x11232970a669> (const data field 0)
 }
0x11232970a6b9: [Map]
 - type: JS_OBJECT_TYPE
 - instance size: 32
 - inobject properties: 1
 - elements kind: HOLEY_ELEMENTS
 - unused property fields: 0
 - enum length: invalid
 - stable_map
 - back pointer: 0x11232970a619 <Map(HOLEY_ELEMENTS)>
 - prototype_validity cell: 0x2a8e03680659 <Cell value= 1>
 - instance descriptors (own) #1: 0x273fe544b2b9 <DescriptorArray[1]>
 - layout descriptor: (nil)
 - prototype: 0x1b89284c20e1 <Object map = 0x112329700209>
 - constructor: 0x1b89284c2119 <JSFunction Object (sfi = 0x2a8e036898e9)>
 - dependent code: 0x1cf27a1c02a1 <Other heap object (WEAK_FIXED_ARRAY_TYPE)>
 - construction counter: 0

DebugPrint: 0x273fe544b269: [JS_OBJECT_TYPE]
 - map: 0x11232970a669 <Map(HOLEY_ELEMENTS)> [FastProperties]
 - prototype: 0x1b89284c20e1 <Object map = 0x112329700209>
 - elements: 0x1cf27a1c0c01 <FixedArray[0]> [HOLEY_ELEMENTS]
 - properties: 0x1cf27a1c0c01 <FixedArray[0]> {
    #q: <unboxed double> 1.1 (const data field 0)
 }
0x11232970a669: [Map]
 - type: JS_OBJECT_TYPE
 - instance size: 32
 - inobject properties: 1
 - elements kind: HOLEY_ELEMENTS
 - unused property fields: 0
 - enum length: invalid
 - stable_map
 - back pointer: 0x11232970a619 <Map(HOLEY_ELEMENTS)>
 - prototype_validity cell: 0x2a8e03680659 <Cell value= 1>
 - instance descriptors (own) #1: 0x273fe544b289 <DescriptorArray[1]>
 - layout descriptor: 0x100000000
 - prototype: 0x1b89284c20e1 <Object map = 0x112329700209>
 - constructor: 0x1b89284c2119 <JSFunction Object (sfi = 0x2a8e036898e9)>
 - dependent code: 0x1cf27a1c02a1 <Other heap object (WEAK_FIXED_ARRAY_TYPE)>
 - construction counter: 0

pwndbg> job 0x273fe544b2b9
0x273fe544b2b9: [DescriptorArray]
 - map: 0x1cf27a1c0251 <Map>
 - enum_cache: empty
 - nof slack descriptors: 0
 - nof descriptors: 1
 - raw marked descriptors: mc epoch 0, marked 0
  [0]: #p (const data field 0:h, p: 0, attrs: [WEC]) @ Class(0x11232970a669)
pwndbg> tel 0x273fe544b2b9-1
00:0000│  0x273fe544b2b8 —▸ 0x1cf27a1c0251 ◂— 0x1cf27a1c01
01:0008│  0x273fe544b2c0 ◂— 0x10001
02:0010│  0x273fe544b2c8 —▸ 0x1cf27a1c2389 ◂— 0x100001cf27a1c23
03:0018│  0x273fe544b2d0 —▸ 0x1b89284df859 ◂— 0x4200001cf27a1c04
04:0020│  0x273fe544b2d8 ◂— 0xc400000000
05:0028│  0x273fe544b2e0 —▸ 0x11232970a66b ◂— 0x4030400001cf27a # field map
06:0030│  0x273fe544b2e8 ◂— 0xdeadbeedbeadbeef
07:0038│  0x273fe544b2f0 ◂— 0xdeadbeedbeadbeef
pwndbg> job 0x1b89284df859
#p
```

可以观察到o对象的instace_descriptor的DescriptorArray中拥有p的map

看似此时可以得到FindFieldOwner返回的应该是字段的map的结论，但是调试过后发现并非如此

![image-20230606153859300](imgs/image-20230606153859300.png)

分析map的FindFieldOwner函数，理论上该函数应当与mapref中的函数返回相同结果

这里进行了一个循环，遍历对象的back pointer链来寻找一个拥有descriptor索引的instance_descriptor，并将具有这个instace_descriptor的对象作为map返回

但是我们这里的back pointer是不存在这个属性的

```
pwndbg> job 0xe2008c0a6b9
0xe2008c0a6b9: [Map]
 - type: JS_OBJECT_TYPE
 - instance size: 32
 - inobject properties: 1
 - elements kind: HOLEY_ELEMENTS
 - unused property fields: 0
 - enum length: invalid
 - stable_map
 - back pointer: 0x0e2008c0a619 <Map(HOLEY_ELEMENTS)>                 # back pointer链
 - prototype_validity cell: 0x0d2e9b9c0659 <Cell value= 1>
 - instance descriptors (own) #1: 0x31de10fcb5c1 <DescriptorArray[1]> # 长度 == 1, 需要找到一个有0索引的对象
 - layout descriptor: (nil)
 - prototype: 0x24c1d11820e1 <Object map = 0xe2008c00209>
 - constructor: 0x24c1d1182119 <JSFunction Object (sfi = 0xd2e9b9c98e9)>
 - dependent code: 0x02f667c402a1 <Other heap object (WEAK_FIXED_ARRAY_TYPE)>
 - construction counter: 0
pwndbg> job 0x0e2008c0a619
0xe2008c0a619: [Map]
 - type: JS_OBJECT_TYPE
 - instance size: 32
 - inobject properties: 1
 - elements kind: HOLEY_ELEMENTS
 - unused property fields: 1
 - enum length: invalid
 - back pointer: 0x02f667c404b1 <undefined>							   # 链尾
 - prototype_validity cell: 0x0d2e9b9c0659 <Cell value= 1>
 - instance descriptors (own) #0: 0x02f667c40239 <DescriptorArray[0]>  # 长度 == 0
 - layout descriptor: (nil)
 - transitions #2: 0x24c1d119fe11 <TransitionArray[6]>Transition array #2:
     #a: (transition to (const data field, attrs: [WEC]) @ Class(0xe2008c0a669)) -> 0x0e2008c0a6b9 <Map(HOLEY_ELEMENTS)>
     #m: (transition to (const data field, attrs: [WEC]) @ Any) -> 0x0e2008c0a669 <Map(HOLEY_ELEMENTS)>

 - prototype: 0x24c1d11820e1 <Object map = 0xe2008c00209>
 - constructor: 0x24c1d1182119 <JSFunction Object (sfi = 0xd2e9b9c98e9)>
 - dependent code: 0x02f667c402a1 <Other heap object (WEAK_FIXED_ARRAY_TYPE)>
 - construction counter: 0
```

所以这个函数最后返回的依然是本对象的map，而不是先前推测的字段属性的map，

而关于之前DescriptorArray中的map的来源，从chromium code search里DescriptorArray的注释中提到结构中的value可能会有一个map的weak reference，但是并没有解释其作用与具体指向

![image-20230606160112227](imgs/image-20230606160112227.png)

我们可以以此推测jsheapbroker实际上会对js对象的一些数据做cache，将对象的字段的owner记录在PropertyDescriptor结构中，这样就省去了每次遍历back pointer的开销

查找一下引用会发现在SerializeOwnDescriptor中，存在对PropertyDescriptor的创建

![image-20230606160605434](imgs/image-20230606160605434.png)

简要分析可以发现该函数透过jsheapbroker更新了map的instance_descriptor中对应属性的PropertyDescriptor信息，验证了我们刚才的推测

![image-20230603201853383](imgs/image-20230603201853383.png)

回到函数，可以确认此时owner为拥有此属性的对象的map

![image-20230606163637241](imgs/image-20230606163637241.png)

![image-20230606163651195](imgs/image-20230606163651195.png)

InstallDependency的逻辑较为简单，更新将code插入map的dependent code字段数组中

我们看到PropertyAccessBuilder的BuildCheckMaps函数的逻辑

![image-20230606162757037](imgs/image-20230606162757037.png)

可以看到这里有两种方式，第一种判断了receiver的map是否stable，如果stable，且根据access_info得到的receiver_maps中确实有这个map，则添加一个StableMap的依赖

否则创建一个checkmaps的node，在运行时鉴别对象的map

这里也说明了v8中有两种deoptimize的机制，一种是通过依赖来标记代码，在运行时若发生了依赖变化，则deoptimize相应代码，另一种则是使用checkmaps的代码来运行时检查map类型是否匹配

map的dependent code就是为了deoptimize而设，当map变为unstable时，即可根据该字段来遍历所有依赖当前stable map的optimized code

![image-20230606164253443](imgs/image-20230606164253443.png)

所有依赖在Commit函数中被Install，时机为编译流水线的结尾

![image-20230606185336157](imgs/image-20230606185336157.png)

此时审视我们最开始得到的patch

```diff
+#if 0
     unrecorded_dependencies.push_back(
         dependencies()->FieldRepresentationDependencyOffTheRecord(map_ref,
                                                                   descriptor));
+#endif
     if (descriptors_field_type->IsClass()) {
       // Remember the field map, and try to infer a useful type.
       Handle<Map> map(descriptors_field_type->AsClass(), isolate());
@@ -384,15 +386,17 @@ PropertyAccessInfo AccessInfoFactory::ComputeDataFieldAccessInfo(
   }
   // TODO(turbofan): We may want to do this only depending on the use
   // of the access info.
+#if 0
   unrecorded_dependencies.push_back(
       dependencies()->FieldTypeDependencyOffTheRecord(map_ref, descriptor));
+#endif
```

FieldType根据一些代码可以知道实际就是指代字段的map

这里将两个依赖注释了，导致当字段属性的representation为HeapObject时，程序没有正确地记录FieldOwner对于field的representation与type的依赖，而记录是通过对map install dependent code来完成的，因此在函数编译后，修改FieldOwner类型理论上也不会

所以理论上可以修改FieldOwner的类型来造成类型混淆



我们还需要确定一下函数的触发路径

在chromium code search中查找一下patch函数引用

![image-20230602155652981](imgs/image-20230602155652981.png)

只出现在ComputePropertyAccessInfo中，继续往下找

![image-20230602155733376](imgs/image-20230602155733376.png)

有两个引用

分别查看一下

![image-20230602155811751](imgs/image-20230602155811751.png)



![image-20230602155915506](imgs/image-20230602155915506.png)

GetPropertyAccessInfo用的更加频繁一些，同时注意到有一个ReduceNamedAccess，这表明turbofan在优化具名属性访问如o.xxx时会引用到这里的结果



## 剖析poc

```javascript
function opt(o) {
    return o.x.y;
}

let obj = {x: {y: 1.1}}
for (let i = 0; i < 100000; i++) opt(obj);

obj.x = {z: {}};
console.log(opt(obj))
```

观察生成的字节码

![image-20230606194647224](imgs/image-20230606194647224.png)

opt函数产生了两次属性访问

通过以下命令进行调试

```bash
gdb --args ./d8 --allow-natives-syntax --trace-opt-verbose --trace-deopt ./poc.js
```

通过turbolizer观察编译过程中的节点变化

![image-20230606194908037](imgs/image-20230606194908037.png)

![image-20230606194304500](imgs/image-20230606194304500.png)

发现产生了两个checkmaps，与我们预期的通过depend code进行deoptimize有些不符

且在loadelimination阶段将第二个checkmaps去除



分析checkmaps的出处

![image-20230602160843157](imgs/image-20230602160843157.png)

![image-20230606194447428](imgs/image-20230606194447428.png)

当receiver转换为string或number失败时调用BuildCheckMaps

![image-20230606194513633](imgs/image-20230606194513633.png)

调试发现m.HasValue()对于两次调用均不成立

![image-20230606195204624](imgs/image-20230606195204624.png)

![image-20230606195247896](imgs/image-20230606195247896.png)

发现此函数需要node的opcode为HeapConstant，难以满足，所以落入checkmaps的path



通过调试也发现dependent code集中在o.x而非o

![image-20230606203223136](imgs/image-20230606203223136.png)

分析loadelimination中发生的事

![image-20230606203403032](imgs/image-20230606203403032.png)

调用ReduceCheckMaps，第一次调用时，node state中没有记录map，通过该checkmaps后更新check的map范围到node state中

再经过ReduceLoadField获取到field的map，更新到node state中，故第二次时map会落入范围中，成功reduce



poc中最后使用了重赋值来修改obj.x的类型，这个操作并不会改变obj的map

同时也注意到obj的初始化方式较为特别

```js
let obj = {x: {y: 1.1}}
```

v8中初始化对象时，若采取以下形式

```js
let a = {b:1,c:2,d:3,e:4,f:5}
```

则v8会尽量优化成a对象中带有5个inline property，直接依附在对象结构上，而不在Properties数组中

同时一个字典默认初始化时，一般会带有4个默认的slot来存放property

```js
let a = {}
a.x0 = 0; // inline
a.x1 = 1; // inline
a.x2 = 2; // inline
a.x3 = 3; // inline
a.x4 = 4; // in properties
```

具体可以参考v8 blogs中的[这篇文章](https://v8.dev/blog/fast-properties)



同时触发混淆的成员名不能与原来相同

```js
let obj = {x: {y: 1.1}}
for (let i = 0; i < 100000; i++) opt(obj);

obj.x = {z: {}};
console.log(opt(obj))
```

即此处的z不能为y

因为这样创造出来的{y:{}}实际是{y:1.1}的泛化

由于v8的field representation generalization机制，当一个field被修改成一个更加泛用的类型的值时，如smi修改为Tagged指针，为了表示这样的转变，v8根据版本不同会有两种处理方式，较早的版本会建立一个新map，将field representation修改为Tagged，将原来的map舍弃，较新的版本考虑到性能问题，会就地进行可兼容的representation转换，但是这两种方法最终都会invalidate code dependency，导致deoptimize

这个逻辑实现在Map::GeneralizeField中

![image-20230613214250869](imgs/image-20230613214250869.png)





