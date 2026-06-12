# Classming Easy

Classming Easy 是对 Classming 原型仓库的整理版本，用于从 Java class seed 自动生成 JVM 差分测试用例。

Classming 来自论文 *Deep Differential Testing of JVM Implementations* (ICSE 2019)。核心思想是执行 seed class，收集 live bytecode，然后在活跃字节码上插入控制流变异（如 `goto`、`return`、`lookupswitch`），生成可运行 mutant。

本仓库额外提供了构建、单 seed 运行、批量运行使用者自行收集的 seed corpus、导出 clean testcase 等脚本。默认导出的 testcase 会删除 Classming 内部的 `Print.logPrint(...)` trace instrumentation，因此更适合接入其他测试框架。

## 环境要求

- JDK 8。Soot 处理 Java 8 class 最稳定，运行脚本会尝试定位 `rt.jar`。
- Bash、`javac`、`java`、`javap`、`rg`、`timeout`。
- Soot/ASM/Guava/Jasmin/java_cup 等外部 jar。

依赖 jar 推荐放在仓库根目录的 `lib/`，或者通过 `CLASSMING_LIB_DIR` 指定：

```bash
CLASSMING_LIB_DIR=/path/to/classming-libs ./build.sh
```

脚本会优先从以下位置寻找外部依赖：

1. `CLASSMING_LIB_DIR`
2. `./lib`
3. `./dependencies`
4. 本机 Maven 缓存 `~/.m2/repository`

至少需要能找到 `soot-*.jar`、`asm-*.jar`、`asm-tree-*.jar`。运行阶段通常还需要 `guava-*.jar`、`jasmin-*.jar`、`java_cup-*.jar` 等 Soot/Jasmin 依赖。如果 JDK 8 不在常规位置，可设置：

```bash
JAVA8_HOME=/path/to/jdk8 ./run.sh --seed com.example.Main --classpath ./seeds
```

## 仓库内容

```text
src/com/classming/                 Classming Java 源码
scripts/classpath.sh               共享 classpath 解析逻辑
build.sh                           编译脚本
run.sh                             单 seed 运行脚本
export_testcases.sh                导出 AcceptHistory 为 clean testcase
run_seed_corpus_batch.sh           批量扫描并运行使用者自行收集的 seed corpus
clean_exported_testcases.sh        清理已有 testcase 中的 Print 插桩
fix_exported_testcase_paths.sh     修复旧版本导出路径中的反斜杠问题
dependencies/                      原仓库已有依赖，部分旧版本 jar 会被脚本跳过
sootOutput/                        原仓库已有示例 seed，不建议提交个人 seed 或输出
```

## 构建

```bash
./build.sh
```

输出目录：

```text
out/production/classming/
```

## Seed Corpus 规约

使用者需要自行准备 seed corpus。本仓库不会提交个人收集的 seed corpus 或生成结果。

一个 seed corpus 应满足以下规约：

1. 输入目录必须包含已经编译好的 `.class` 文件。
2. `--classpath` 或 `--classpath-root` 必须指向 Java package root，而不是任意上层目录。
3. class 文件路径必须与包名一致。例如 `array.ArrayNesting` 必须位于 `<classpath-root>/array/ArrayNesting.class`。
4. 默认批处理只运行带 `public static void main(String[])` 的 class；没有 main 的 class 会被跳过。
5. seed class 的 `main` 最好无需交互输入，且能在限定时间内结束。
6. seed corpus 中若有辅助类，应与 seed class 放在同一个 classpath root 下，或通过额外 classpath 机制提供。
7. 不建议直接在原始 seed corpus 上运行 Classming；批处理脚本会复制一份工作副本再运行，避免污染原始文件。
8. 如果输入目录使用 IDE 输出结构，例如 `out/production/<project>`，批处理脚本可在只有一个 project 输出目录时自动识别；其他结构可用 `--classpath-root` 手动指定。

示例结构：

```text
my-seeds/
└── out/production/classes/
    ├── array/
    │   └── ArrayNesting.class
    ├── bit_manipulation/
    │   └── HammingDistance.class
    └── helper/
        └── Utils.class
```

对应 classpath root：

```text
my-seeds/out/production/classes
```

## 单个 seed 运行

```bash
./run.sh \
  --seed <fully.qualified.MainClass> \
  --iterations 20 \
  --classpath <seed-classpath-root>
```

示例：

```bash
./run.sh \
  --seed example.Main \
  --iterations 20 \
  --classpath ./my-seeds/out/production/classes/
```

参数：

```text
--seed <class>       目标 seed class 的全限定名
--iterations <N>     mutation 迭代次数
--classpath <path>   seed classpath root，必须是包路径的根目录
--args <a,b,c>       传给 seed main(String[]) 的参数，逗号分隔
--deps <j1;j2>       额外依赖，沿用原项目格式
--jvm-opts <opts>    执行 seed 时使用的 JVM 参数
```

单 seed 运行会产生内部目录：

```text
AcceptHistory/       accepted mutant 内部快照
RejectHistory/       rejected mutant 内部快照
tmp/                 临时 mutant
nolivecode/          无 live code 的 mutant
```

`AcceptHistory/` 不是最终 testcase 目录。它的文件名形如 `timestamp.pkg.Class.class`，需要导出后才能作为标准 classpath 使用。

## 导出 clean testcase

```bash
./export_testcases.sh --history AcceptHistory --out generated-tests
```

导出结构：

```text
generated-tests/
└── <mutant-id>/
    └── pkg/
        └── Class.class
```

导出时会删除 `Print.logPrint(...)` 插桩，并且不会复制 `Print.class`。运行方式：

```bash
java -cp "generated-tests/<mutant-id>:<original-seed-classpath-root>" <seed-class>
```

## 批量运行 Seed Corpus

`run_seed_corpus_batch.sh` 会复制一份输入 seed corpus 到输出目录的 `work/` 中，避免污染原始 seed。它默认只运行带有 `public static void main(String[])` 的 class。

小规模冒烟测试：

```bash
./run_seed_corpus_batch.sh \
  --input my-seeds \
  --classpath-root my-seeds/out/production/classes \
  --out generated-seed-tests-smoke \
  --iterations 2 \
  --timeout 90 \
  --limit 10
```

正式运行：

```bash
./run_seed_corpus_batch.sh \
  --input my-seeds \
  --classpath-root my-seeds/out/production/classes \
  --out generated-seed-tests \
  --iterations 20 \
  --timeout 180
```

参数：

```text
--input <dir>            seed corpus 根目录
--classpath-root <dir>   手动指定 seed classpath root，通常不需要
--out <dir>              输出目录
--iterations <N>         每个 seed 的 mutation 迭代次数
--timeout <seconds>      每个 seed 的最大运行时间
--limit <N>              最多处理 N 个 seed，0 表示不限制
--run-all                不检查 main(String[])，所有 class 都尝试运行
--keep-history           保留每轮内部 AcceptHistory/RejectHistory/tmp
--workdir <dir>          手动指定工作副本目录
```

输出结构：

```text
generated-seed-tests/
├── manifest.tsv
├── logs/
│   └── <seed>.log
├── raw/
│   └── <mutant-id>.<seed>.class        未清理的原始 Classming mutant，供调试
├── testcases/
│   └── <seed-name>/
│       └── <mutant-id>/
│           └── pkg/
│               └── Class.class         clean testcase
└── work/
    ├── seed-corpus/                    输入 seed corpus 的工作副本
    └── clean-root/                     未变异依赖 classpath root
```

`manifest.tsv` 记录每个 testcase 的运行命令：

```text
seed    mutant_id    testcase_dir    seed_classpath    run_command
```

批量运行导出的 testcase：

```bash
awk -F '\t' 'NR > 1 {print $1 "\t" $3 "\t" $4}' generated-seed-tests/manifest.tsv | while IFS=$'\t' read -r seed testcase_dir seed_cp; do
  java -cp "$testcase_dir:$seed_cp" "$seed"
done
```

## 批量运行非标准文件名 Class Corpus

有些高质量 seed corpus 的 class 文件不是标准 Java package 路径布局，例如文件可能是：

```text
classHistory/compiler.c1.TestUnalignedLoad/compiler.c1.TestUnalignedLoad-origin.class
```

但 class 内部真实名字是：

```text
compiler.c1.TestUnalignedLoad
```

这种目录不能直接作为 classpath root 传给 `run_seed_corpus_batch.sh`。应使用 `run_classfile_corpus_batch.sh`，它会读取每个 `.class` 的内部类名，并为每个 seed 创建标准化运行目录。

示例：

```bash
./run_classfile_corpus_batch.sh \
  --input sootOutput/HotSpot \
  --out generated-hotspot-tests \
  --iterations 3 \
  --timeout 60
```

参数：

```text
--input <dir>        class 文件 corpus 根目录，可以包含非标准文件名
--out <dir>          输出目录
--iterations <N>     每个 seed 的 mutation 迭代次数
--timeout <seconds>  每个 seed 的最大运行时间
--limit <N>          最多处理 N 个 seed，0 表示不限制
--run-all            不检查 main(String[])，所有 class 都尝试运行
```

输出结构：

```text
generated-hotspot-tests/
├── manifest.tsv
├── logs/
├── raw/
├── testcases/
│   └── <seed-id>/
│       └── <mutant-id>/
│           └── pkg/
│               └── Class.class
└── work/
    ├── deps/<seed-id>/     标准化后的原始依赖 classpath root
    └── run/<seed-id>/      Classming 运行时使用的可改写副本
```

`manifest.tsv` 多一列 `source_class`，记录该 testcase 来自哪个原始 class 文件。

## 清理已有输出中的 Print 插桩

如果你用旧脚本生成过带 `Print.class` 和 `Print.logPrint(...)` 的 testcase，可原地清理：

```bash
./clean_exported_testcases.sh generated-seed-tests
```

该脚本会删除 testcase 目录下的 `Print.class`，并重写每个 mutant class，去掉 `Print.logPrint(...)` 调用。

## 修复旧版本导出路径

早期脚本曾把包路径导出成带反斜杠的目录，例如 `array\`。修复命令：

```bash
./fix_exported_testcase_paths.sh generated-seed-tests
```

## 差分测试多个 JVM

可以对 `manifest.tsv` 中的 testcase 用多个 JVM 运行并比较输出：

```bash
awk -F '\t' 'NR > 1 {print $1 "\t" $3 "\t" $4}' generated-seed-tests/manifest.tsv | while IFS=$'\t' read -r seed testcase_dir seed_cp; do
  jenv exec 1.8 java -cp "$testcase_dir:$seed_cp" "$seed" > /tmp/jdk8.out 2>&1 || true
  jenv exec 17 java -cp "$testcase_dir:$seed_cp" "$seed" > /tmp/jdk17.out 2>&1 || true
  diff /tmp/jdk8.out /tmp/jdk17.out || echo "JVM difference: $testcase_dir"
done
```

## 不应提交的内容

以下是本地运行产物或个人测试用例，不应上传远程仓库：

```text
out/
tmp/
AcceptHistory/
RejectHistory/
nolivecode/
generated-*/
batch-*/
clean-batch-*/
sootOutput/leetcodes*/
sootOutput/*_seeds*/
sootOutput/seeds*/
lib/
*.log
*.zip
```

如果要分享 seed 或生成结果，建议另建 artifact/release，不要直接放进源码仓库。
