1. Spark中RDD、DataFrame和Dataset的区别是什么？

   - **RDD（Resilient Distributed Dataset）**：是Spark最底层的数据抽象，是一个不可变的、分区的、容错的集合。RDD没有Schema信息，不支持SQL操作，需要用户自己处理序列化和反序列化，性能较低但灵活性最高。适用于非结构化数据或需要底层控制的场景。
   - **DataFrame**：是以命名列组织的数据集，类似于关系数据库中的表。DataFrame有Schema信息，支持SQL查询，使用Catalyst优化器和Tungsten引擎进行优化，性能比RDD高。但DataFrame是弱类型的，编译期不检查类型安全。适用于结构化数据处理。
   - **Dataset**：是DataFrame的扩展，结合了RDD的类型安全和DataFrame的性能优势。Dataset是强类型的，编译期可以检查类型错误。Dataset使用Encoder机制进行序列化，可以按需访问单个字段，避免反序列化整个对象。在Spark 2.0+中，DataFrame实际上是`Dataset[Row]`的类型别名。

   | 特性 | RDD | DataFrame | Dataset |
   |------|-----|-----------|--------|
   | 类型安全 | 编译期检查 | 运行时检查 | 编译期检查 |
   | Schema | 无 | 有 | 有 |
   | SQL支持 | 不支持 | 支持 | 支持 |
   | 优化器 | 无 | Catalyst | Catalyst |
   | 序列化 | Java/Kryo | Tungsten | Tungsten |
   | 适用场景 | 非结构化数据 | 结构化数据 | 结构化+类型安全 |
2. 什么是Spark的宽依赖和窄依赖？请举例说明。

   - **窄依赖（Narrow Dependency）**：父RDD的每个分区最多被子RDD的一个分区使用。窄依赖不会触发Shuffle，可以在同一个Stage内以流水线方式执行。
     - 一对一关系：`map`、`filter`、`union`等
     - 选择性依赖：`coalesce`（父分区被选择性地分配给子分区）
   - **宽依赖（Wide Dependency / Shuffle Dependency）**：父RDD的每个分区被子RDD的多个分区使用。宽依赖会触发Shuffle操作，是Stage划分的边界。
     - 典型算子：`groupByKey`、`reduceByKey`、`join`、`distinct`、`repartition`等

   **区分意义**：
   - 窄依赖允许在同一个Executor上流水线执行，减少网络IO
   - 宽依赖是Stage划分的依据，Shuffle过程需要跨节点数据传输
   - 窄依赖的容错恢复成本低（只需重新计算丢失的父分区），宽依赖的容错恢复成本高（可能需要重新计算所有父分区）
3. Spark的Stage是如何划分的？为什么要这样划分？

   **Stage划分规则**：
   - 从最后一个RDD开始向前回溯，遇到宽依赖（Shuffle依赖）就划分一个新的Stage
   - 每个宽依赖生成一个新的Stage边界
   - 窄依赖的RDD划分在同一个Stage中
   - 最终会形成一个或多个Stage的DAG图

   **划分流程**：
   1. DAGScheduler从Action算子触发，反向遍历RDD依赖链
   2. 遇到窄依赖，将RDD加入当前Stage
   3. 遇到宽依赖，将当前Stage切分，创建新的Stage
   4. 宽依赖两端的RDD分别属于不同的Stage

   **为什么要这样划分**：
   - **减少网络传输**：窄依赖可以在同一节点上流水线执行，避免数据跨节点传输
   - **提高并行度**：不同Stage之间可以并行执行（无依赖关系的Stage）
   - **容错效率**：Stage边界是容错恢复的最小单位，窄依赖只需重新计算少量分区
   - **资源调度**：以Stage为单位进行任务调度和资源分配
4. 什么是Spark Shuffle？哪些算子会触发Shuffle？

   **Shuffle定义**：Shuffle是Spark中跨分区重新分配数据的机制。当数据需要按照某个Key重新分组或排序时，就需要将数据在不同Executor之间进行传输，这个过程就是Shuffle。Shuffle涉及磁盘IO、网络传输和数据序列化，是Spark性能的关键瓶颈。

   **Shuffle过程**：
   - **Shuffle Write**：Map端将数据按Key分区写入本地磁盘
   - **Shuffle Read**：Reduce端从各个Map端拉取属于自己的分区数据

   **触发Shuffle的算子**：
   - **聚合类**：`reduceByKey`、`aggregateByKey`、`combineByKey`、`foldByKey`
   - **分组类**：`groupByKey`、`groupBy`
   - **排序类**：`sortByKey`、`sortBy`
   - **Join类**：`join`、`leftOuterJoin`、`rightOuterJoin`、`fullOuterJoin`、`cogroup`
   - **去重类**：`distinct`
   - **重分区类**：`repartition`、`coalesce`（shuffle=true时）
   - **交集类**：`intersection`

   **注意**：`reduceByKey`虽然触发Shuffle，但在Map端有预聚合（combine），可以减少Shuffle数据量；而`groupByKey`没有预聚合，所有数据直接Shuffle传输。
5. Spark为什么比MapReduce快？

   1. **内存计算**：Spark优先使用内存进行中间结果的存储，减少了大量的磁盘IO。MapReduce的中间结果必须写入磁盘（Map端输出到本地磁盘，Reduce端再从磁盘读取）。
   2. **DAG执行引擎**：Spark将任务构建成DAG（有向无环图），可以根据依赖关系优化执行计划，将多个操作合并到一个Stage中流水线执行。MapReduce只有Map和Reduce两个阶段，多步骤任务需要写多次磁盘。
   3. **惰性求值（Lazy Evaluation）**：Spark的Transformation操作是惰性的，直到Action触发才真正执行，Catalyst优化器可以全局优化执行计划。MapReduce每个Job立即执行。
   4. **多线程模型**：Spark的Task在同一Executor中以多线程方式运行，Task启动开销小。MapReduce每个Task是一个JVM进程，启动开销大。
   5. **数据缓存**：Spark支持将数据缓存到内存中（cache/persist），迭代式计算场景下避免重复读取磁盘。MapReduce没有缓存机制。
   6. **Shuffle优化**：Spark的Shuffle支持SortShuffleManager，Map端可以预聚合，减少数据传输量。
   7. **Tungsten优化**：Spark 1.4+引入Tungsten引擎，使用堆外内存、代码生成（Whole-Stage CodeGen）等技术大幅提升CPU和内存效率。
6. 请描述Spark Application的提交流程。

   **以Spark on YARN Cluster模式为例**：

   1. **提交应用**：客户端使用`spark-submit`提交应用，指定主类、资源参数等。
   2. **资源申请**：客户端向ResourceManager申请启动ApplicationMaster。
   3. **启动ApplicationMaster**：ResourceManager在NodeManager上分配Container，启动ApplicationMaster（即Spark的Driver进程）。
   4. **初始化SparkContext**：ApplicationMaster中初始化SparkContext，创建DAGScheduler和TaskScheduler。
   5. **注册Application**：ApplicationMaster向ResourceManager注册自己，申请运行Executor所需的资源。
   6. **启动Executor**：ResourceManager分配Container后，ApplicationMaster在对应NodeManager上启动Executor进程。
   7. **Executor注册**：Executor启动后向Driver（ApplicationMaster）反向注册。
   8. **任务调度**：Driver将Application代码转化为Job，DAGScheduler划分Stage生成TaskSet，TaskScheduler将Task分发到Executor执行。
   9. **任务执行**：Executor接收到Task后，在TaskRunner中运行，运行结果汇报给Driver。
   10. **应用完成**：所有Job执行完毕，Driver注销Application，释放资源。

   **核心组件交互**：
   - SparkContext → DAGScheduler → TaskScheduler → SchedulerBackend → Executor
7. Spark on YARN的Client模式和Cluster模式有什么区别？

   | 对比项 | Client模式 | Cluster模式 |
   |--------|-----------|-------------|
   | Driver运行位置 | 提交任务的客户端进程 | YARN集群的ApplicationMaster中 |
   | ApplicationMaster职责 | 仅负责申请资源 | 既是Driver又负责申请资源 |
   | 客户端是否可退出 | 否，Driver在客户端运行，退出则应用失败 | 是，提交后客户端可退出 |
   | 日志查看 | 日志在客户端控制台直接输出 | 需通过YARN日志查看 |
   | 网络开销 | Driver与Executor可能跨网络通信 | Driver与Executor在同一集群内通信 |
   | 适用场景 | 交互式调试、开发测试 | 生产环境部署 |
   | 资源占用 | 占用提交机器资源 | 不占用提交机器资源 |

   **Client模式流程**：
   1. 客户端启动Driver（SparkContext）
   2. 向RM申请资源启动ApplicationMaster
   3. ApplicationMaster申请Container启动Executor
   4. Executor向客户端Driver注册并执行任务

   **Cluster模式流程**：
   1. 客户端向RM提交应用
   2. RM在NodeManager上启动ApplicationMaster（即Driver）
   3. ApplicationMaster申请Container启动Executor
   4. Executor向ApplicationMaster中的Driver注册并执行任务
8. 什么是Spark的广播变量？它有什么作用？

   **定义**：广播变量是Spark提供的一种分布式共享只读变量机制。它允许Driver将一个只读变量高效地分发到每个Executor上，而不是每个Task都携带一份副本。

   **使用方式**：
   ```scala
   val broadcastVar = sc.broadcast(Array(1, 2, 3))
   val value = broadcastVar.value
   ```

   **作用**：
   1. **减少网络传输**：不使用广播变量时，每个Task的闭包都会包含该变量的序列化副本，导致大量重复数据在网络中传输。使用广播变量后，每个Executor只接收一份副本，该Executor上的所有Task共享这一份。
   2. **节省内存**：避免在每个Task中保存一份变量副本，减少Executor内存占用。
   3. **优化Join操作**：大表Join小表时，可以将小表广播到所有Executor，使用Map Join（Broadcast Join）代替Shuffle Join，避免Shuffle操作。

   **注意事项**：
   - 广播变量是只读的，不能在Executor端修改
   - 广播变量应在Driver端创建，在Executor端读取
   - 广播大变量时注意Executor内存是否足够
   - 使用后可调用`unpersist`释放资源
9. 什么是Spark的累加器？

   **定义**：累加器是Spark提供的一种分布式只写共享变量机制，用于在Executor端进行分布式计数或求和，最终将结果聚合到Driver端。

   **使用方式**：
   ```scala
   val acc = sc.longAccumulator("myAccumulator")
   rdd.foreach(x => acc.add(x))
   println(acc.value)
   ```

   **特点**：
   1. **只写**：Executor端只能对累加器进行add操作，不能读取value
   2. **聚合**：各Executor的累加结果最终在Driver端聚合
   3. **容错**：累加器在Task失败重试时不会重复计算（保证Exactly-Once语义）

   **注意事项**：
   - 在Transformation操作中使用累加器时，如果RDD被重复计算（如cache被驱逐后重新计算），累加器可能重复累加。建议在Action操作中使用累加器。
   - 只有Driver端可以读取累加器的最终值

   **自定义累加器**：Spark 2.0+支持通过继承`AccumulatorV2`自定义累加器，可以实现复杂的数据结构聚合，如Collection累加器等。
10. Spark中`reduceByKey`和`groupByKey`的区别是什么？

   | 对比项 | reduceByKey | groupByKey |
   |--------|-------------|------------|
   | Map端预聚合 | 有（combine） | 无 |
   | Shuffle数据量 | 小（预聚合后传输） | 大（全量数据传输） |
   | 返回类型 | RDD[(K, V)] | RDD[(K, Iterable[V])] |
   | 性能 | 高 | 低 |
   | 内存占用 | 低 | 高（需缓存所有值） |

   **核心区别**：
   - `reduceByKey`在Shuffle Write之前会在Map端先进行本地聚合（combine），相同Key的数据在本地先合并，只将聚合结果传输到Reduce端，大大减少了Shuffle数据量。
   - `groupByKey`不会在Map端预聚合，所有数据原封不动地参与Shuffle，Reduce端收到的每个Key对应一个值的迭代器。

   **示例**：
   ```scala
   // reduceByKey: Map端预聚合，Shuffle数据量小
   rdd.reduceByKey(_ + _)
   
   // groupByKey: 无预聚合，Shuffle数据量大
   rdd.groupByKey().mapValues(_.sum)
   ```

   **建议**：
   - 需要聚合操作时，优先使用`reduceByKey`、`aggregateByKey`等带预聚合的算子
   - 只有确实需要获取每个Key的所有值时才使用`groupByKey`
11. 什么是Spark的数据倾斜？如何定位和解决？

   **定义**：数据倾斜是指在Shuffle过程中，由于Key分布不均匀，导致部分Task处理的数据量远大于其他Task，造成少数Task执行时间极长（长尾任务），严重影响整体性能。

   **现象**：
   - 绝大多数Task很快完成，少数Task运行时间极长
   - 某些Task出现OOM或GC时间过长
   - Spark UI上可以看到各Task处理的数据量差异极大

   **定位方法**：
   1. 查看Spark UI的Stage页面，观察Task的数据倾斜程度（Shuffle Read Size/Records）
   2. 查看Task的执行时间分布，是否有长尾
   3. 使用`sample`算子采样数据，分析Key分布
   4. 查看Executor日志，是否有OOM错误

   **解决方案**：
   1. **过滤异常Key**：如果倾斜Key是无意义的（如null、空串），直接过滤掉
   2. **增加Shuffle分区数**：增大`spark.sql.shuffle.partitions`，让数据更均匀分布
   3. **两阶段聚合**：对倾斜Key加随机前缀，先局部聚合，再去除前缀进行全局聚合（适用于聚合类操作）
   4. **Broadcast Join**：大表Join小表时，将小表广播，避免Shuffle Join
   5. **加盐拆分**：将倾斜Key的数据打散到多个分区处理，最后再合并结果
   6. **自定义Partitioner**：根据数据分布自定义分区策略，使数据均匀分布
12. Spark的内存管理模型是怎样的？

   Spark 1.6+采用统一内存管理模型（UnifiedMemoryManager），将Executor内存分为以下几个区域：

   **整体内存结构**：
   ```
   |--- 总内存 (spark.executor.memory) ---|
   |  堆内内存  |  堆外内存 (spark.memory.offHeap.size)  |
   ```

   **堆内内存划分**：
   1. **Reserved Memory**（保留内存）：约300MB，系统预留
   2. **User Memory**（用户内存）：约占25%，用于存储用户数据结构和UDF等
   3. **Spark Memory**（执行和存储内存）：约占75%，又分为：
      - **Storage Memory**（存储内存）：缓存RDD、广播变量等
      - **Execution Memory**（执行内存）：Shuffle、Join、Sort、聚合等操作的内存

   **关键机制**：
   - **动态占用**：Storage和Execution内存可以互相借用。Execution内存不足时可以借用空闲的Storage内存，反之亦然。但当一方需要被借用的内存时，另一方必须立即归还。
   - **Execution内存不可被驱逐**：Execution内存中的数据正在使用中，不能被驱逐；Storage内存中的缓存数据可以被驱逐（LRU）。
   - **堆外内存**：Spark可以使用堆外内存（Off-Heap），避免JVM GC开销，由Tungsten管理。
13. 什么是Spark的Checkpoint？它和Cache/Persist有什么区别？

   **Checkpoint定义**：Checkpoint是将RDD的数据写入HDFS等可靠存储系统，并截断RDD的依赖链（血缘关系）。Checkpoint后的RDD不再依赖父RDD，容错时直接从Checkpoint文件读取数据，无需重新计算。

   **Checkpoint vs Cache/Persist**：

   | 对比项 | Checkpoint | Cache/Persist |
   |--------|-----------|---------------|
   | 存储位置 | HDFS等可靠外部存储 | 内存/本地磁盘 |
   | 血缘关系 | 截断血缘，不依赖父RDD | 保留血缘，缓存失效后可重新计算 |
   | 持久性 | 持久化，应用退出后仍存在 | 临时性，应用结束后自动清除 |
   | 容错性 | 高，数据存储在可靠存储系统 | 低，内存数据可能因节点故障丢失 |
   | 执行时机 | 需要单独触发（需先cache再checkpoint提高效率） | 惰性触发，Action时缓存 |
   | 适用场景 | 血缘链过长、关键中间结果 | 重复使用的RDD |

   **使用建议**：
   ```scala
   // 推荐先cache再checkpoint，避免checkpoint时重新计算RDD
   rdd.cache()
   rdd.checkpoint()
   ```
   先cache使得checkpoint时直接从内存读取数据写入HDFS，避免重新计算整个血缘链。
14. Spark SQL的执行原理是什么？

   Spark SQL的执行流程如下：

   1. **SQL/DataFrame解析**：将SQL语句或DataFrame操作解析为**未解析的逻辑执行计划**（Unresolved Logical Plan），此时表名、列名等尚未与实际Schema绑定。

   2. **分析（Analysis）**：Catalyst优化器结合Catalog（元数据信息）对未解析的逻辑计划进行绑定，将表名映射到实际表、列名映射到实际列，生成**已解析的逻辑执行计划**（Resolved Logical Plan）。

   3. **逻辑优化（Logical Optimization）**：Catalyst优化器基于规则（RBO）对逻辑计划进行优化，包括：常量折叠、谓词下推、列裁剪、常量替换等，生成**优化后的逻辑执行计划**（Optimized Logical Plan）。

   4. **物理计划生成（Physical Planning）**：将逻辑计划转化为一个或多个**物理执行计划**（Physical Plans），基于代价（CBO）选择最优的物理计划，生成**最终物理执行计划**（Final Physical Plan）。

   5. **代码生成（Code Generation）**：通过Whole-Stage CodeGen将物理计划生成Java字节码，在Executor上执行。

   **Catalyst优化器核心**：
   - 基于Scala的函数式编程，使用树形结构表示计划
   - 使用Rule对树进行变换和优化
   - 支持自定义扩展（如数据源优化规则）
15. 什么是谓词下推和列裁剪？

   **谓词下推（Predicate Pushdown）**：
   - 将过滤条件（谓词）尽可能下推到数据源端执行，在读取数据时就进行过滤，减少后续处理的数据量。
   - 例如：`SELECT name FROM users WHERE age > 20`，不使用谓词下推时先读取所有数据再过滤；使用谓词下推后，在读取数据时就只读取age>20的记录。
   - 好处：减少IO读取量、减少内存占用、减少网络传输（如果数据源支持过滤，如Parquet、ORC等）。

   **列裁剪（Column Pruning）**：
   - 只读取查询中实际需要的列，跳过不需要的列，减少数据读取量。
   - 例如：`SELECT name FROM users`，不使用列裁剪时读取所有列；使用列裁剪后只读取name列。
   - 对于列式存储格式（Parquet、ORC），列裁剪效果尤为显著，因为数据按列存储，可以直接跳过不需要的列。

   **两者结合**：
   ```sql
   SELECT name FROM users WHERE age > 20
   -- 谓词下推：在数据源端过滤 age > 20
   -- 列裁剪：只读取 name 和 age 列（age用于过滤，name用于输出）
   ```
   这两种优化是Catalyst优化器中基于规则优化（RBO）的典型代表。
16. Spark Streaming和Structured Streaming的区别是什么？

   | 对比项 | Spark Streaming | Structured Streaming |
   |--------|----------------|---------------------|
   | 编程模型 | DStream（微批处理RDD） | DataFrame/Dataset（无界表） |
   | 处理模型 | 微批处理（Micro-batch） | 微批处理 + 连续处理（Continuous） |
   | 延迟 | 秒级（批间隔决定） | 毫秒级（Continuous模式）~秒级 |
   | API | DStream API（RDD风格） | DataFrame/Dataset API + SQL |
   | 事件时间处理 | 需手动实现 | 原生支持Watermark |
   | 延迟数据处理 | 无内置支持 | Watermark机制自动处理 |
   | 端到端一致性 | 需手动实现 | Exactly-Once内置保证 |
   | 优化器 | 无Catalyst优化 | Catalyst + Tungsten优化 |
   | 输出模式 | 仅Append | Append、Update、Complete |
   | 状态管理 | updateStateByKey/mapWithState | mapGroupsWithState/flatMapGroupsWithState |

   **Structured Streaming核心思想**：
   - 将流数据视为一个不断增长的无界表
   - 每个新到达的数据就像是在表中追加一行
   - 查询在这个无界表上执行，就像在静态表上执行批处理查询一样
   - Spark自动增量执行查询，并持续更新结果
17. 什么是Spark的DAG？它是如何生成的？

   **DAG定义**：DAG（Directed Acyclic Graph，有向无环图）是Spark中用于表示RDD之间依赖关系的图结构。DAG中的节点是RDD，边是RDD之间的转换关系（依赖关系）。

   **DAG生成过程**：
   1. **构建RDD血缘关系**：用户编写的Transformation算子会生成新的RDD，每个RDD记录其父RDD和计算逻辑，形成RDD的血缘链。
   2. **Action触发Job**：当调用Action算子时，Spark会根据该Action对应的RDD向前回溯，构建完整的DAG。
   3. **DAGScheduler处理DAG**：
      - 从最后一个RDD（Result RDD）开始反向遍历依赖链
      - 遇到窄依赖，将RDD加入当前Stage
      - 遇到宽依赖，切分新的Stage边界
      - 最终将DAG拆分为多个Stage，每个Stage内部是窄依赖的RDD流水线
   4. **生成TaskSet**：每个Stage被转化为TaskSet提交给TaskScheduler执行

   **DAG的优势**：
   - 避免了MapReduce中多Job之间的磁盘IO
   - 允许流水线执行窄依赖操作
   - 支持全局优化（Catalyst优化器）
   - 便于容错恢复（根据血缘重新计算丢失分区）
18. Spark的Driver和Executor分别负责什么？

   **Driver（驱动器）**：
   - 运行Application的`main()`函数，是Spark应用的主进程
   - **核心职责**：
     1. 创建`SparkContext`/`SparkSession`
     2. 将用户代码转化为Spark作业（Job）
     3. DAGScheduler：将Job划分为Stage，构建DAG
     4. TaskScheduler：将Task分发到Executor执行
     5. 监控Task执行状态，处理失败重试
     6. 管理广播变量和累加器
     7. 协调Executor之间的数据交换（Shuffle）

   **Executor（执行器）**：
   - 运行在工作节点上的进程，负责执行具体的计算任务
   - **核心职责**：
     1. 执行Driver分配的Task，并将结果返回给Driver
     2. 使用BlockManager管理Executor上的数据块（包括缓存的RDD数据）
     3. 为Shuffle操作提供数据（Shuffle Read/Write）
     4. 存储广播变量的副本
     5. 以线程池方式运行Task（每个Task一个线程）

   **交互关系**：
   - Driver向Executor发送Task
   - Executor向Driver注册并汇报Task状态
   - Shuffle过程中Executor之间直接传输数据
19. 什么是Spark的Lineage（血缘）？它有什么作用？

   **定义**：Lineage（血缘）是Spark中RDD之间的依赖关系链。每个RDD都记录了它是如何从父RDD转换而来的（包括转换算子和依赖类型），这些依赖关系构成了RDD的血缘关系图。

   **血缘的作用**：
   1. **容错恢复**：当某个RDD的分区数据丢失时（如Executor故障），Spark可以根据血缘关系重新计算丢失的分区，而不需要从头开始计算整个Job。这是Spark高效容错的核心机制。
   2. **避免数据复制**：与Hadoop通过数据复制实现容错不同，Spark通过血缘关系实现容错，避免了大量数据复制的存储开销。
   3. **优化执行计划**：Catalyst优化器可以根据血缘关系进行逻辑优化（如谓词下推、列裁剪等）。
   4. **调试和监控**：通过`toDebugString`可以查看RDD的血缘关系，帮助理解执行计划。

   **血缘与Checkpoint的关系**：
   - 血缘链过长时，容错恢复成本高（需要重新计算大量父RDD）
   - Checkpoint可以截断血缘链，将中间结果持久化到可靠存储，降低容错恢复成本

   **查看血缘**：
   ```scala
n   rdd.toDebugString  // 查看RDD的血缘关系
   rdd.dependencies    // 查看RDD的直接依赖
   ```
20. Spark中`map`和`flatMap`的区别是什么？

   | 对比项 | map | flatMap |
   |--------|-----|---------|
   | 输入输出关系 | 一对一：每个输入元素产生一个输出元素 | 一对多：每个输入元素产生0到多个输出元素 |
   | 返回类型 | RDD[T] → RDD[U] | RDD[T] → RDD[U]（展平） |
   | 输出元素数量 | 与输入相同 | 可能多于或少于输入 |
   | 空值处理 | 不能过滤元素 | 可以通过返回空集合过滤元素 |

   **示例**：
   ```scala
   val rdd = sc.parallelize(Seq("hello world", "spark"))
   
   // map: 一对一映射
   rdd.map(_.split(" "))
   // 结果: Array[Array[String]] = Array(Array("hello", "world"), Array("spark"))
   
   // flatMap: 一对多映射并展平
   rdd.flatMap(_.split(" "))
   // 结果: Array[String] = Array("hello", "world", "spark")
   ```

   **使用场景**：
   - `map`：对每个元素进行简单转换，如类型转换、字段提取、数值计算
   - `flatMap`：文本分词、一对多展开、需要过滤某些元素的场景（返回空集合即可过滤）
21. 什么是Spark的Shuffle Map Stage和Result Stage？

   - **Shuffle Map Stage**：是DAG中除最后一个Stage之外的所有Stage。它的Task类型为ShuffleMapTask，执行结果需要通过Shuffle传递给下游Stage。Shuffle Map Stage的输出不是最终结果，而是为下游Stage准备数据（写入本地磁盘供Shuffle Read拉取）。
   - **Result Stage**：是DAG中最后一个Stage，直接触发Job的执行。它的Task类型为ResultTask，执行结果就是Action算子的最终输出（如collect、count、save等）。

   **区别**：

   | 对比项 | Shuffle Map Stage | Result Stage |
   |--------|-------------------|-------------|
   | Task类型 | ShuffleMapTask | ResultTask |
   | 输出方式 | 写入本地磁盘供Shuffle | 直接返回结果给Driver或写入外部存储 |
   | 数量 | 一个Job可以有多个 | 一个Job只有一个 |
   | 位置 | DAG的中间部分 | DAG的末端 |
   | 触发条件 | 下游Stage需要其数据 | Action算子触发 |

   **执行顺序**：Shuffle Map Stage必须先执行完毕，Result Stage才能开始执行（因为Result Stage依赖Shuffle Map Stage的Shuffle输出）。
22. Spark中`repartition`和`coalesce`的区别是什么？

   | 对比项 | repartition | coalesce |
   |--------|-------------|----------|
   | 分区数变化 | 可增可减 | 主要用于减少分区 |
   | 是否Shuffle | 一定触发Shuffle | 默认不触发Shuffle（shuffle=false） |
   | 性能 | 较低（需要Shuffle） | 较高（减少分区时不Shuffle） |
   | 数据均匀性 | 均匀 | 可能不均匀 |

   **核心区别**：
   - `repartition(numPartitions)`：等价于`coalesce(numPartitions, shuffle=true)`，无论增加还是减少分区都会触发Shuffle，数据均匀分布。
   - `coalesce(numPartitions, shuffle=false)`：减少分区时不触发Shuffle，通过合并同一Executor上的分区实现，效率高但可能导致数据不均匀（某些分区数据量远大于其他分区）。

   **使用建议**：
   - 减少分区且不关心数据均匀性时，使用`coalesce`，避免Shuffle开销
   - 增加分区或需要数据均匀分布时，使用`repartition`
   - 过滤大量数据后分区数据量变小，使用`coalesce`减少分区数，避免大量空分区或小分区
   - 注意：`coalesce`增大分区数且shuffle=false时无效（分区数不会改变），必须设置shuffle=true或使用`repartition`
23. 什么是Spark的Map Join？它的实现原理是什么？

   **Map Join（Broadcast Join）**：是一种优化Join操作的方式，当参与Join的一张表足够小（可以放入Executor内存）时，将小表广播到所有Executor节点，在Map端直接完成Join，避免Shuffle操作。

   **实现原理**：
   1. **小表广播**：Driver将小表的数据收集到Driver端，然后通过Broadcast机制将小表分发到每个Executor的内存中。
   2. **Map端Join**：每个Executor在处理大表的每个分区时，直接与内存中的小表进行Join匹配，不需要Shuffle大表数据。
   3. **结果输出**：Join结果直接输出，无需经过Shuffle阶段。

   **触发条件**：
   - Spark SQL中，当小表大小小于`spark.sql.autoBroadcastJoinThreshold`（默认10MB）时，Catalyst优化器会自动选择Broadcast Join
   - 也可以通过Hint手动指定：`/*+ BROADCAST(t) */`

   **优势**：
   - 避免Shuffle操作，大幅减少网络IO和磁盘IO
   - 消除数据倾斜风险（大表不需要Shuffle）
   - 执行速度快

   **限制**：
   - 小表必须能放入Executor内存
   - 广播大表会导致OOM和网络拥塞
24. Spark中如何自定义Partitioner？

   **自定义Partitioner步骤**：

   1. 继承`org.apache.spark.Partitioner`抽象类
   2. 实现`numPartitions`方法：返回分区数量
   3. 实现`getPartition`方法：根据Key返回分区编号（0到numPartitions-1）
   4. 可选：重写`equals`和`hashCode`方法，确保分区器比较逻辑正确

   **示例**：
   ```scala
   class MyPartitioner(numParts: Int) extends Partitioner {
     override def numPartitions: Int = numParts
     
     override def getPartition(key: Any): Int = {
       key match {
         case k: String => k.hashCode % numPartitions
         case _ => 0
       }
     }
     
     override def equals(obj: Any): Boolean = obj match {
       case p: MyPartitioner => p.numPartitions == numPartitions
       case _ => false
     }
     
     override def hashCode: Int = numPartitions
   }
   
   // 使用自定义Partitioner
   val partitionedRdd = rdd.partitionBy(new MyPartitioner(10))
   ```

   **使用场景**：
   - 数据分布不均匀，默认Hash分区导致数据倾斜
   - 需要按业务逻辑将相关数据分配到同一分区
   - 多个RDD需要使用相同分区策略进行Join优化
25. 什么是Spark的External Shuffle Service？

   **定义**：External Shuffle Service是一个独立于Spark Executor运行的辅助服务，负责管理Shuffle文件的读取。它通常以YARN Auxiliary Service的形式运行在每个NodeManager上。

   **作用**：
   1. **Executor解耦**：Shuffle文件由External Shuffle Service管理，即使Executor退出，Shuffle文件仍然可以被其他Executor读取。没有该服务时，Executor退出后其Shuffle文件不可用，下游Stage需要重新计算。
   2. **动态资源分配**：配合Dynamic Allocation使用，允许空闲的Executor被释放，而不影响Shuffle数据的可用性。
   3. **减少资源占用**：Executor不需要持续运行来提供Shuffle数据服务，释放后资源可以被其他应用使用。

   **配置方式**：
   ```properties
   # Spark端配置
   spark.shuffle.service.enabled=true
   spark.shuffle.service.port=7337
   
   # YARN端配置（yarn-site.xml）
   yarn.nodemanager.aux-services=spark_shuffle
   yarn.nodemanager.aux-services.spark_shuffle.class=org.apache.spark.network.yarn.YarnShuffleService
   ```

   **工作原理**：
   - Executor在Shuffle Write时将数据文件和索引文件写入本地磁盘
   - External Shuffle Service监听指定端口，响应Shuffle Read请求
   - 下游Executor从External Shuffle Service拉取Shuffle数据
26. Spark中`cache`和`persist`的区别是什么？

   - **cache**：等价于`persist(MEMORY_ONLY)`，将RDD以反序列化Java对象的形式存储在内存中。如果内存不足，部分分区不会被缓存，后续使用时需要重新计算。
   - **persist**：可以指定存储级别，灵活控制缓存的位置和方式。

   **存储级别**：

   | 存储级别 | 说明 |
   |--------|------|
   | MEMORY_ONLY | 仅存内存，反序列化对象（默认cache级别） |
   | MEMORY_ONLY_SER | 仅存内存，序列化数据（节省空间，需额外CPU反序列化） |
   | MEMORY_AND_DISK | 内存优先，放不下则写磁盘 |
   | MEMORY_AND_DISK_SER | 内存优先，序列化存储，放不下写磁盘 |
   | DISK_ONLY | 仅存磁盘 |
   | MEMORY_ONLY_2 / MEMORY_AND_DISK_2 | 同上，但复制2份到不同节点（容错） |

   **选择建议**：
   - 内存充足：`MEMORY_ONLY`（最快）
   - 内存紧张：`MEMORY_ONLY_SER`（节省空间，序列化开销小）
   - 数据重要且内存不够：`MEMORY_AND_DISK`
   - 需要高容错：带`_2`后缀的级别

   **注意**：
   - `cache`和`persist`都是惰性操作，需要Action触发才会真正缓存
   - 使用`unpersist`手动释放缓存
   - 同一个RDD多次调用`persist`，只有第一次生效
27. 什么是Spark的AQE（Adaptive Query Execution）？

   **定义**：AQE（自适应查询执行）是Spark 3.0引入的优化机制，在运行时根据实际的统计信息动态调整执行计划，而不是仅依赖编译期的静态优化。

   **启用方式**：
   ```properties
   spark.sql.adaptive.enabled=true
   ```

   **三大核心优化**：

   1. **动态合并Shuffle分区（Dynamic Coalescing Shuffle Partitions）**：
      - 问题：Shuffle分区数设置不合理，导致小分区过多，Task调度开销大
      - 优化：运行时根据Shuffle数据量自动合并小分区，减少Task数量
      - 配置：`spark.sql.adaptive.coalescePartitions.enabled=true`

   2. **动态切换Join策略（Dynamic Switch Join Strategies）**：
      - 问题：编译期估计小表适合Broadcast Join，但运行时发现数据量超过阈值
      - 优化：运行时检测到广播表超过阈值，自动从Broadcast Join切换为Sort-Merge Join
      - 配置：`spark.sql.adaptive.localShuffleReader.enabled=true`

   3. **动态优化数据倾斜（Dynamic Optimize Skew Join）**：
      - 问题：Join时某些分区数据量远大于其他分区，导致长尾任务
      - 优化：运行时检测倾斜分区，将倾斜分区拆分为多个子分区并行处理
      - 配置：`spark.sql.adaptive.skewJoin.enabled=true`
28. Spark SQL中DataFrame和Dataset的关系是什么？

   **关系**：
   - 在Spark 2.0+中，DataFrame是`Dataset[Row]`的类型别名：`type DataFrame = Dataset[Row]`
   - DataFrame是Dataset的一种特殊形式，其类型为Row（弱类型）
   - Dataset是更通用的抽象，支持强类型（如`Dataset[Person]`）

   **对比**：

   | 对比项 | DataFrame | Dataset |
   |--------|-----------|--------|
   | 类型 | Dataset[Row]（弱类型） | Dataset[T]（强类型） |
   | 类型检查 | 运行时 | 编译期 |
   | API风格 | SQL风格 / 无类型API | 函数式 / 类型化API |
   | 访问字段 | `df.col("name")` 或 `df("name")` | `ds.map(_.name)` |
   | 错误发现 | 运行时才发现字段名错误 | 编译期发现类型错误 |
   | 适用语言 | Scala/Java/Python/R | Scala/Java |

   **转换方式**：
   ```scala
   // DataFrame → Dataset
   val ds = df.as[Person]
   
   // Dataset → DataFrame
   val df = ds.toDF()
   ```

   **注意**：Python/R不支持Dataset强类型API，只能使用DataFrame。
29. 什么是Spark的Tungsten优化？

   **定义**：Tungsten是Spark 1.4引入的优化项目，目标是大幅提升Spark的执行效率，主要通过优化CPU和内存使用来实现，而非优化IO和网络（这些已经接近硬件极限）。

   **核心优化**：

   1. **堆外内存管理（Off-Heap Memory）**：
      - 使用Unsafe API直接操作堆外内存，避免JVM对象的额外开销
      - 减少GC压力，内存占用更紧凑

   2. **缓存感知计算（Cache-Aware Computation）**：
      - 设计对CPU L1/L2缓存友好的数据结构
      - 减少缓存未命中，提高CPU利用率

   3. **Whole-Stage Code Generation（全阶段代码生成）**：
      - Spark 2.0引入，将多个物理算子融合为一个Java函数
      - 消除虚函数调用开销，利用JIT编译优化
      - 避免中间数据的序列化/反序列化

   4. **紧凑数据结构**：
      - 使用二进制格式存储数据，减少内存占用
      - 例如：将UTF-8字符串存储为定长字节数组+偏移量

   **效果**：
   - 内存占用减少数倍
   - CPU效率提升数倍
   - GC时间大幅减少
30. Spark中如何处理小文件问题？

   **小文件问题**：大量小文件会导致NameNode内存压力大（HDFS中每个文件约占150B元数据）、读取时大量小Task导致调度开销大、文件打开关闭开销大。

   **解决方案**：

   1. **读取时合并**：
      - 使用`spark.sql.files.maxPartitionBytes`（默认128MB）控制单个分区读取的最大字节数
      - 使用`spark.sql.files.openCostInBytes`（默认4MB）估算打开文件的开销，促使小文件合并到同一分区
      - 使用`spark.hadoop.mapreduce.input.fileinputformat.split.maxsize`控制InputSplit大小

   2. **写入时合并**：
      - 使用`coalesce`或`repartition`减少输出分区数，从而减少输出文件数
      - 使用`spark.sql.shuffle.partitions`控制Shuffle后的分区数

   3. **输出后合并**：
      - 使用Hadoop Archive（HAR）将小文件打包
      - 定期运行合并任务，将小文件合并为大文件

   4. **使用Delta Lake / Hudi / Iceberg**：
      - 这些数据湖框架支持自动Compaction（压缩合并）小文件
      - 支持Optimize命令主动合并小文件

   5. **分区策略优化**：
      - 避免过度分区，合理设置分区粒度
      - 使用`partitionBy`写入时控制分区数
31. 什么是Spark的DPP（Dynamic Partition Pruning）？

   **定义**：DPP（动态分区裁剪）是Spark 3.0引入的优化特性，在运行时根据维表过滤条件动态裁剪事实表的分区，避免扫描不需要的分区数据。

   **适用场景**：
   - 事实表（大表）按分区列存储，维表（小表）有过滤条件
   - Join操作中，一侧为分区表，另一侧有过滤条件

   **原理**：
   ```sql
   SELECT * FROM fact_table f JOIN dim_table d
   ON f.partition_col = d.partition_col
   WHERE d.other_col = 'value'
   ```
   - 传统方式：先扫描fact_table所有分区，再与dim_table Join
   - DPP优化：先从dim_table获取满足条件的partition_col值，构建子查询过滤器，在扫描fact_table时直接跳过不匹配的分区

   **启用条件**：
   ```properties
   spark.sql.optimizer.dynamicPartitionPruning.enabled=true  # 默认true
   spark.sql.optimizer.dynamicPartitionPruning.useStats=true  # 使用统计信息判断是否值得DPP
   spark.sql.optimizer.dynamicPartitionPruning.fallbackFilterRatio=0.5  # 回退过滤比例
   spark.sql.optimizer.dynamicPartitionPruning.reuseBroadcastOnly=true  # 是否仅复用Broadcast的子查询
   ```

   **效果**：大幅减少事实表的扫描数据量，提升查询性能。
32. Spark中`union`和`unionByName`的区别是什么？

   | 对比项 | union | unionByName |
   |--------|-------|-------------|
   | 列匹配方式 | 按位置匹配（第1列对第1列） | 按列名匹配 |
   | 列顺序要求 | 必须一致 | 可以不一致 |
   | 列名处理 | 不检查列名，结果使用左表的列名 | 按列名对齐，结果使用左表的列名 |
   | 列数不同 | 报错 | 允许（需设置allowMissingColumns=true） |
   | 引入版本 | Spark 1.0 | Spark 2.3 |

   **示例**：
   ```scala
   // df1: [name: string, age: int]
   // df2: [age: int, name: string]
   
   df1.union(df2)
   // 结果：name列会混入age数据，age列会混入name数据（按位置匹配，不安全）
   
   df1.unionByName(df2)
   // 结果：正确按列名对齐，name对name，age对age
   ```

   **建议**：
   - 列顺序一致时，两者结果相同
   - 列顺序不确定或不一致时，使用`unionByName`更安全
   - 生产环境推荐使用`unionByName`，避免因列顺序不一致导致的数据错误
33. 什么是Spark的Push-based Shuffle？

   **定义**：Push-based Shuffle是Spark 3.2引入的Shuffle优化机制，改变了传统Shuffle的拉取（Pull）模式，采用推送（Push）模式将Shuffle数据推送到远程Shuffle Service。

   **传统Shuffle（Pull模式）**：
   - Map Task将Shuffle数据写入本地磁盘
   - Reduce Task从各个Map节点拉取（Fetch）自己需要的数据
   - 问题：Reduce Task需要等待所有Map Task完成才能开始拉取；大量并发拉取导致网络拥塞

   **Push-based Shuffle（Push模式）**：
   - Map Task完成Shuffle Write后，主动将数据推送到远程Shuffle Service
   - 远程Shuffle Service将同一Reduce分区的数据合并（Merge）成大文件
   - Reduce Task从合并后的大文件中读取数据，减少随机IO

   **优势**：
   1. 减少Reduce Task的随机IO，提升Shuffle Read性能
   2. 数据合并后文件更少，减少文件打开数
   3. 可以更早发现数据倾斜
   4. 配合Remote Shuffle Service效果更好

   **配置**：
   ```properties
   spark.shuffle.push.enabled=true
   spark.shuffle.push.server.port=8020
   ```

   **限制**：需要配合Remote Shuffle Service使用，目前仅支持特定Shuffle Service实现。
34. Spark中如何优化Join操作？

   **Join优化策略**：

   1. **Broadcast Join（Map Join）**：
      - 小表广播到所有Executor，避免Shuffle
      - 适用：小表 < `spark.sql.autoBroadcastJoinThreshold`（默认10MB）
      - Hint：`/*+ BROADCAST(t) */`

   2. **Sort-Merge Join**：
      - 两表按Join Key排序后合并，适合大表Join大表
      - Spark 2.3+默认Join策略
      - 配置：`spark.sql.join.preferSortMergeJoin=true`

   3. **Bucket Join**：
      - 两表按Join Key分桶存储，Join时无需Shuffle
      - 适用于经常Join的大表
      - 建表时指定：`CLUSTERED BY (col) INTO N BUCKETS`

   4. **倾斜Join优化**：
      - 启用AQE的skewJoin优化：`spark.sql.adaptive.skewJoin.enabled=true`
      - 手动拆分倾斜Key，加盐处理后Join

   5. **分区裁剪**：
      - Join前过滤不需要的分区，减少数据量
      - 启用DPP：`spark.sql.optimizer.dynamicPartitionPruning.enabled=true`

   6. **调整并行度**：
      - 增大`spark.sql.shuffle.partitions`，减少每个Task的数据量
      - 避免单个Task数据量过大

   7. **列裁剪**：Join前只选择需要的列，减少数据量

   8. **Map端预聚合**：Join前先对数据预聚合，减少Shuffle数据量
35. 什么是Spark的Watermark（水位线）？

   **定义**：Watermark是Structured Streaming中用于处理迟到数据的机制。它设定一个阈值，表示允许数据迟到多长时间，超过该阈值的迟到数据将被丢弃。

   **原理**：
   - Watermark基于事件时间（Event Time）而非处理时间（Processing Time）
   - 引擎跟踪当前观察到的最大事件时间，Watermark = 最大事件时间 - 延迟阈值
   - 事件时间小于Watermark的数据被视为迟到数据，会被丢弃

   **使用方式**：
   ```scala
   // 设置Watermark，允许数据迟到10分钟
   val watermarkedDF = df
     .withWatermark("timestamp", "10 minutes")
     .groupBy(window($"timestamp", "5 minutes"), $"word")
     .count()
   ```

   **作用**：
   1. **处理迟到数据**：设定合理的延迟阈值，平衡数据完整性和延迟
   2. **释放状态资源**：Watermark之前的窗口状态可以被清理，避免状态无限增长
   3. **确定窗口关闭时间**：当Watermark超过窗口结束时间，该窗口不再接收新数据

   **注意**：
   - Watermark必须在Group By之前设置
   - 延迟阈值设置过大会导致状态占用过多内存
   - 延迟阈值设置过小会导致过多数据被丢弃
   - Watermark只对基于事件时间的窗口聚合有效
36. Spark Streaming中DStream和RDD的关系是什么？

   **关系**：DStream（Discretized Stream）是Spark Streaming的核心抽象，代表一个连续的数据流。DStream本质上是一系列连续的RDD的集合，每个RDD包含一个时间间隔（batch interval）内的数据。

   **结构**：
   ```
   DStream = RDD[0] + RDD[1] + RDD[2] + ... + RDD[n]
              |        |        |              |
           batch0   batch1   batch2        batchn
           t0-t1    t1-t2    t2-t3         tn-tn+1
   ```

   **核心要点**：
   - 每个batch interval生成一个RDD
   - DStream上的操作会转化为对每个RDD的相应操作
   - DStream的Transformation是惰性的，Output Operation触发实际计算
   - DStream之间可以存在依赖关系（类似RDD的血缘关系）

   **DStream → RDD的转化**：
   - `dstream.map(f)` → 每个RDD执行`rdd.map(f)`
   - `dstream.reduceByKey(f)` → 每个RDD执行`rdd.reduceByKey(f)`
   - `dstream.foreachRDD(f)` → 对每个batch的RDD执行函数f

   **与Structured Streaming对比**：
   - DStream基于RDD，是微批处理模型
   - Structured Streaming基于DataFrame/Dataset，支持连续处理模式
37. 什么是Spark的Exactly-Once语义？如何保证？

   **三种消息语义**：
   - **At Most Once**：最多一次，消息可能丢失，不会重复
   - **At Least Once**：至少一次，消息不会丢失，可能重复
   - **Exactly Once**：精确一次，消息不丢失不重复，最理想但最难实现

   **Spark中的Exactly-Once保证**：

   1. **Structured Streaming的Exactly-Once**：
      - **端到端Exactly-Once**：通过Checkpoint + WAL（Write-Ahead Log）+ 幂等性Sink实现
      - 步骤：
        a. 从Source读取数据时记录Offset（Checkpoint存储）
        b. 处理数据并将结果写入Sink
        c. 更新Checkpoint中的Offset
      - 如果失败重启，从Checkpoint恢复，重新读取并处理，Sink需支持幂等写入或事务写入

   2. **Spark Streaming的Exactly-Once**：
      - 通过Checkpoint机制保存处理进度
      - Output Operation需要是幂等的（重复执行结果相同）
      - 或使用事务写入（将Offset和结果在同一事务中提交）

   3. **关键条件**：
      - **可重放Source**：如Kafka，支持从指定Offset重新读取
      - **幂等/事务Sink**：如数据库事务、HDFS幂等写入
      - **Checkpoint持久化**：保存处理进度，故障后可恢复

   **Kafka + Structured Streaming示例**：
   ```scala
   spark.readStream.format("kafka")
     .option("startingOffsets", "earliest")
     .load()
     .writeStream.format("console")
     .option("checkpointLocation", "/checkpoint")
     .start()
   ```
38. Spark中`filter`和`where`的区别是什么？

   **结论**：在Spark SQL / DataFrame API中，`filter`和`where`**完全等价**，没有功能上的区别。

   **源码层面**：
   ```scala
   // DataFrame API中，where只是filter的别名
   def where(conditionExpr: String): DataFrame = filter(conditionExpr)
   def where(condition: Column): DataFrame = filter(condition)
   ```

   **使用方式**：
   ```scala
   // 以下两种写法完全等价
   df.filter($"age" > 20)
   df.where($"age" > 20)
   
   // SQL字符串形式也等价
   df.filter("age > 20")
   df.where("age > 20")
   ```

   **为什么两个都有**：
   - `filter`是函数式编程的传统命名（Scala/Python标准库中的过滤方法）
   - `where`是SQL风格的命名，更贴近SQL语法，方便SQL用户使用

   **建议**：
   - 代码中统一使用一种风格即可
   - SQL风格代码用`where`，函数式风格代码用`filter`
39. 什么是Spark的Sort-Merge Join？

   **定义**：Sort-Merge Join（排序合并Join）是Spark 2.3+默认的Join策略，适用于大表Join大表的场景。它将两表先按Join Key排序，然后合并匹配的行。

   **执行流程**：

   1. **Shuffle阶段**：两表按Join Key进行Hash Shuffle，相同Key的数据分配到同一分区
   2. **Sort阶段**：每个分区内，两表分别按Join Key排序
   3. **Merge阶段**：对两个已排序的数据集进行归并匹配，输出Join结果

   **优势**：
   - 内存友好：排序后可以流式合并，不需要将一侧数据全部加载到内存
   - 适合大表Join：即使两表都很大也能处理
   - 可扩展性强：数据量增大时性能下降平缓
   - 支持Range Join优化

   **与其他Join策略对比**：

   | Join策略 | 适用场景 | 是否Shuffle | 内存要求 |
   |----------|---------|-------------|----------|
   | Broadcast Join | 小表+大表 | 否 | 小表能放入内存 |
   | Sort-Merge Join | 大表+大表 | 是 | 中等 |
   | Hash Join | 中表+大表 | 是 | 一侧能放入内存 |

   **配置**：
   ```properties
   spark.sql.join.preferSortMergeJoin=true  # 默认true
   ```
40. Spark中如何查看执行计划？

   **1. explain方法**：
   ```scala
   // 查看物理执行计划
   df.explain()
   
   // 查看所有执行计划（详细模式）
   df.explain(extended = true)
   // 输出依次包括：
   // == Parsed Logical Plan ==     （解析后的逻辑计划）
   // == Analyzed Logical Plan ==    （分析后的逻辑计划）
   // == Optimized Logical Plan ==   （优化后的逻辑计划）
   // == Physical Plan ==           （物理执行计划）
   ```

   **2. Spark SQL EXPLAIN**：
   ```sql
   EXPLAIN EXTENDED SELECT * FROM t1 JOIN t2 ON t1.id = t2.id
   ```

   **3. Spark UI**：
   - 访问 `http://driver-host:4040`
   - Jobs页面：查看Job列表和执行状态
   - Stages页面：查看Stage的DAG图和详细信息
   - SQL页面：查看SQL查询的执行计划图

   **4. 执行计划关键信息**：
   - `BroadcastHashJoin`：Broadcast Join（小表广播）
   - `SortMergeJoin`：排序合并Join
   - `Exchange`：Shuffle操作
   - `Filter`：过滤操作
   - `Project`：列选择
   - `FileScan`：文件扫描，可查看读取的分区和列

   **5. 查看RDD血缘**：
   ```scala
   rdd.toDebugString  // 查看RDD的完整血缘链
   ```
41. 什么是Spark的Shuffle Write和Shuffle Read？

   **Shuffle Write（Map端）**：
   - 发生在Shuffle Map Task中，将数据按Key的Hash值或Range分区写入本地磁盘
   - 每个Map Task生成一个数据文件（data file）和一个索引文件（index file）
   - 索引文件记录每个分区在数据文件中的起始偏移量
   - Shuffle Write有三种实现：
     - **BypassMergeSortShuffleWriter**：不需要排序和预聚合，直接按分区写入（如groupByKey）
     - **SortShuffleWriter**：需要排序，数据先排序再按分区写入（如sortByKey）
     - **UnsafeShuffleWriter**：使用Tungsten优化，序列化后直接操作二进制数据排序

   **Shuffle Read（Reduce端）**：
   - 发生在Result Task或后续Shuffle Map Task中
   - 从所有Map Task的输出中拉取属于自己的分区数据
   - 拉取过程中进行反序列化、排序、聚合等操作
   - 可以边拉取边处理（流式处理），也可以全部拉取后再处理

   **数据流转**：
   ```
   Map Task → Shuffle Write → 本地磁盘 → 网络传输 → Shuffle Read → Reduce Task
   ```n
   **优化点**：
   - Map端预聚合（combine）减少Shuffle数据量
   - 压缩Shuffle数据减少网络传输
   - 批量拉取减少网络请求次数
42. Spark中`aggregateByKey`和`combineByKey`的区别是什么？

   **aggregateByKey**：
   ```scala
   def aggregateByKey[U](zeroValue: U)(seqOp: (U, V) => U, combOp: (U, U) => U): RDD[(K, U)]
   ```
   - 三个参数：零值、分区内聚合函数（seqOp）、分区间聚合函数（combOp）
   - seqOp在Map端每个分区内执行，将Value聚合为U类型
   - combOp在Reduce端执行，将各分区的U类型结果合并
   - 零值在每个分区和分区间合并时都会使用

   **combineByKey**：
   ```scala
   def combineByKey[C](createCombiner: V => C, mergeValue: (C, V) => C, mergeCombiners: (C, C) => C): RDD[(K, C)]
   ```
   - 三个参数：创建组合器函数、分区内合并函数、分区间合并函数
   - createCombiner：对每个Key的第一个Value，创建初始聚合值
   - mergeValue：分区内将后续Value合并到聚合值
   - mergeCombiners：分区间合并各分区的聚合值

   **核心区别**：

   | 对比项 | aggregateByKey | combineByKey |
   |--------|---------------|-------------|
   | 初始值 | 固定的zeroValue | 动态创建（createCombiner） |
   | 灵活性 | 较低 | 较高 |
   | 类型转换 | V → U（可变类型） | V → C（灵活） |
   | 底层实现 | 基于combineByKey实现 | 底层API |

   **示例**：
   ```scala
   // aggregateByKey: 求平均值
   rdd.aggregateByKey((0, 0))(
     (acc, v) => (acc._1 + v, acc._2 + 1),  // 分区内: (sum, count)
     (acc1, acc2) => (acc1._1 + acc2._1, acc1._2 + acc2._2)  // 分区间
   )
   
   // combineByKey: 求平均值
   rdd.combineByKey(
     v => (v, 1),                              // 创建组合器
     (acc: (Int, Int), v) => (acc._1 + v, acc._2 + 1),  // 分区内合并
     (acc1: (Int, Int), acc2: (Int, Int)) => (acc1._1 + acc2._1, acc1._2 + acc2._2)  // 分区间合并
   )
   ```
43. 什么是Spark的Dynamic Allocation（动态资源分配）？

   **定义**：Dynamic Allocation是Spark的资源动态管理机制，根据工作负载动态申请和释放Executor，在任务多时增加Executor，任务少时释放空闲Executor。

   **工作原理**：
   1. **申请Executor**：当有Pending Task等待执行时，向资源管理器申请更多Executor
   2. **释放Executor**：当Executor空闲超过一定时间后，释放该Executor

   **配置参数**：
   ```properties
   # 启用动态资源分配
   spark.dynamicAllocation.enabled=true
   
   # 最少Executor数
   spark.dynamicAllocation.minExecutors=0
   
   # 最多Executor数
   spark.dynamicAllocation.maxExecutors=30
   
   # Executor空闲超时时间（毫秒），超时后释放
   spark.dynamicAllocation.executorIdleTimeout=60s
   
   # 缓存Executor空闲超时时间（有缓存的Executor）
   spark.dynamicAllocation.cachedExecutorIdleTimeout=300s
   
   # 初始Executor数
   spark.dynamicAllocation.initialExecutors=2
   
   # 调度超时时间
   spark.dynamicAllocation.schedulerBacklogTimeout=1s
   
   # 每次申请的Executor数
   spark.dynamicAllocation.maxPendingAllocations=10
   ```

   **前提条件**：
   - 必须启用External Shuffle Service，否则Executor释放后Shuffle数据不可用
   - 在YARN上使用时需配置YARN的Shuffle Service

   **优势**：提高集群资源利用率，多个Spark应用共享集群资源。
44. Spark中如何处理数据倾斜导致的OOM？

   **OOM原因**：数据倾斜时，某些Task处理的数据量远大于其他Task，导致该Task内存不足，触发OOM。

   **解决方案**：

   1. **增加Executor内存**：
      - 增大`spark.executor.memory`
      - 增大`spark.executor.memoryOverhead`（堆外内存）
      - 治标不治本，但可以临时缓解

   2. **增加分区数**：
      - 增大`spark.sql.shuffle.partitions`（默认200）
      - 使每个分区的数据量减少

   3. **过滤异常Key**：
      - 空值、空字符串等异常Key可能导致倾斜
      - 在Shuffle前先过滤掉这些Key

   4. **两阶段聚合**（适用于聚合操作）：
      - 第一阶段：对Key加随机前缀，局部聚合
      - 第二阶段：去除前缀，全局聚合

   5. **Broadcast Join**（适用于Join操作）：
      - 大表Join小表时，将小表广播，避免Shuffle
      - 消除Shuffle阶段的数据倾斜

   6. **加盐拆分**（适用于Join操作）：
      - 将倾斜Key的数据复制多份，每份加不同前缀
      - 另一表对应膨胀，使数据均匀分布

   7. **使用Off-Heap内存**：
      - 启用`spark.memory.offHeap.enabled=true`
      - 减少JVM GC压力，降低OOM风险

   8. **调整内存比例**：
      - 增大Execution内存比例
      - `spark.memory.fraction`（默认0.6）
45. 什么是Spark的BlockManager？

   **定义**：BlockManager是Spark的存储系统核心组件，负责管理Spark中所有数据的存储（包括RDD缓存、Shuffle数据、广播变量等）。每个Driver和Executor上都有一个BlockManager实例。

   **架构**：
   ```
   BlockManagerMaster（Driver端）
       ↕  元数据同步
   BlockManager（Executor端）
       ├── BlockTransferService  # 数据传输服务
       ├── MemoryStore           # 内存存储
       ├── DiskStore             # 磁盘存储
       └── BlockInfoManager       # 块元数据管理
   ```

   **核心组件**：
   - **BlockManagerMaster**：运行在Driver端，维护所有Block的元数据信息（位置、大小等），提供Block的查找和定位服务
   - **MemoryStore**：管理堆内和堆外内存中的Block存储
   - **DiskStore**：管理磁盘上的Block存储，每个Block对应一个磁盘文件
   - **BlockTransferService**：负责跨节点的Block数据传输（Shuffle Fetch等）

   **Block的生命周期**：
   1. Block的创建（put）：数据写入MemoryStore或DiskStore
   2. Block的读取（get）：优先从MemoryStore读取，未命中则从DiskStore读取
   3. Block的淘汰（evict）：内存不足时按LRU策略淘汰Storage Block
   4. Block的删除（remove）：unpersist或应用结束时删除

   **Block类型**：
   - RDD缓存Block：`rdd_<id>_<partition>`
   - Shuffle数据Block：`shuffle_<shuffleId>_<mapId>_<reduceId>`
   - 广播变量Block：`broadcast_<id>`
46. Spark中`mapPartitions`和`map`的区别是什么？

   | 对比项 | map | mapPartitions |
   |--------|-----|---------------|
   | 处理粒度 | 每个元素 | 每个分区（迭代器） |
   | 函数输入 | 单个元素 | 分区的迭代器 |
   | 函数输出 | 单个元素 | 迭代器 |
   | 外部资源初始化 | 每个元素初始化一次 | 每个分区初始化一次 |

   **核心区别**：
   - `map`对RDD中的每个元素执行一次函数
   - `mapPartitions`对RDD中的每个分区执行一次函数，函数接收该分区所有元素的迭代器

   **示例**：
   ```scala
   // map: 每个元素创建一次数据库连接（低效）
   rdd.map(x => {
     val conn = DriverManager.getConnection(url)  // 每个元素创建连接！
     val result = conn.executeQuery(x)
     conn.close()
     result
   })
   
   // mapPartitions: 每个分区创建一次数据库连接（高效）
   rdd.mapPartitions(iter => {
     val conn = DriverManager.getConnection(url)  // 每个分区只创建一次
     val results = iter.map(x => conn.executeQuery(x))
     conn.close()
     results
   })
   ```

   **mapPartitions的优势**：
   - 减少外部资源（数据库连接、文件句柄等）的创建和销毁开销
   - 减少函数调用的额外开销

   **mapPartitions的劣势**：
   - 分区数据量过大时可能导致OOM（整个分区的数据在内存中）
   - 需要注意资源的正确释放

   **建议**：涉及外部资源操作时优先使用`mapPartitions`
47. 什么是Spark的Checkpoint目录？

   **定义**：Checkpoint目录是Spark执行Checkpoint时存储RDD数据的HDFS路径。Checkpoint将RDD的数据以二进制文件的形式写入该目录。

   **设置方式**：
   ```scala
   sc.setCheckpointDir("hdfs://namenode:8020/spark/checkpoint")
   ```

   **目录结构**：
   ```
   /spark/checkpoint/
   ├── <job-id>/
   │   ├── rdd-{rdd-id}/
   │   │   ├── part-00000   # 分区0的数据文件
   │   │   ├── part-00001   # 分区1的数据文件
   │   │   └   ...
   ```

   **注意事项**：
   1. **必须设置**：使用Checkpoint前必须先设置Checkpoint目录，否则会报错
   2. **可靠存储**：目录应设置在HDFS等可靠的分布式文件系统上，而非本地文件系统
   3. **目录清理**：Checkpoint文件不会自动清理，需要定期手动清理或通过脚本删除
   4. **先Cache再Checkpoint**：推荐先cache RDD再checkpoint，避免Checkpoint时重新计算整个血缘链
   5. **惰性执行**：Checkpoint是惰性操作，需要Action触发才会真正执行
   6. **Spark Streaming**：Streaming的Checkpoint还保存DStream的元数据和Offset信息，用于故障恢复
48. Spark SQL中UDF、UDAF、UDTF的区别是什么？

   **UDF（User-Defined Function）**：
   - 一进一出：输入一行数据，输出一个值
   - 类似SQL中的`UPPER()`、`SUBSTRING()`等标量函数
   - 示例：
   ```scala
   val upperUDF = udf((s: String) => s.toUpperCase)
   spark.sql("SELECT upper_udf(name) FROM users")
   ```

   **UDAF（User-Defined Aggregate Function）**：
   - 多进一出：输入多行数据，输出一个聚合值
   - 类似SQL中的`COUNT()`、`SUM()`、`AVG()`等聚合函数
   - 需要实现：`initialize`、`update`、`merge`、`evaluate`四个方法
   - 示例：自定义求中位数的UDAF
   ```scala
   class MedianUDAF extends UserDefinedAggregateFunction {
     def initialize(buffer: MutableAggregationBuffer): Unit = ???
     def update(buffer: MutableAggregationBuffer, input: Row): Unit = ???
     def merge(buffer1: MutableAggregationBuffer, buffer2: Row): Unit = ???
     def evaluate(buffer: Row): Any = ???
   }
   ```

   **UDTF（User-Defined Table-Generating Function）**：
   - 一进多出：输入一行数据，输出多行数据（表生成函数）
   - 类似Hive中的`EXPLODE()`、`JSON_TUPLE()`等
   - Spark 2.0+中通过`flatMap`或Generator实现
   - 示例：
   ```scala
   // 使用explode函数（内置UDTF）
   df.select(explode(split($"tags", ",")))
   ```

   **对比**：

   | 类型 | 输入 | 输出 | 典型函数 |
   |------|------|------|----------|
   | UDF | 一行 | 一个值 | UPPER, SUBSTRING |
   | UDAF | 多行 | 一个聚合值 | COUNT, SUM, AVG |
   | UDTF | 一行 | 多行 | EXPLODE, JSON_TUPLE |
49. 什么是Spark的Shuffle Spill？

   **定义**：Shuffle Spill是指Shuffle过程中，内存不足以容纳所有数据时，将部分数据溢写到磁盘的机制。Spill分为Shuffle Write Spill和Shuffle Read Spill。

   **Shuffle Write Spill**：
   - 在SortShuffleWriter中，Map端需要将数据按Key排序后写入
   - 排序过程中，内存不足以存放所有数据时，将部分已排序的数据Spill到磁盘
   - 最终将多个Spill文件合并（Merge）成一个有序的数据文件

   **Shuffle Read Spill**：
   - Reduce端拉取数据后，需要在内存中缓存和聚合数据
   - 当内存不足时，将部分数据Spill到磁盘
   - 最终合并磁盘上的Spill文件，完成聚合和排序

   **触发条件**：
   - `spark.shuffle.spill=true`（默认开启）
   - 数据量超过Execution内存限制时触发

   **影响**：
   - 增加磁盘IO开销
   - 增加GC压力（Spill涉及大量对象的序列化和反序列化）
   - 降低性能

   **减少Spill的方法**：
   1. 增大Executor内存
   2. 调整`spark.memory.fraction`增大Execution内存比例
   3. 增加分区数，减少每个Task的数据量
   4. Map端预聚合（combine），减少Shuffle数据量
   5. 使用序列化存储减少内存占用
50. Spark中如何优化数据倾斜？

   **数据倾斜优化全景**：

   **一、数据读取阶段倾斜**：
   - 问题：某些分区文件特别大
   - 方案：调整`spark.sql.files.maxPartitionBytes`，增大分区容量使小文件合并

   **二、Shuffle阶段倾斜（最常见）**：
   1. **增加Shuffle分区数**：
      - `spark.sql.shuffle.partitions`从默认200增大到合适值
      - 使数据更均匀分布到更多分区

   2. **两阶段聚合**（聚合类操作）：
      - 第一阶段：Key加随机前缀 → 局部聚合
      - 第二阶段：去除前缀 → 全局聚合
      - 打散倾斜Key，均匀分布到多个分区

   3. **Broadcast Join**（Join操作）：
      - 小表广播到所有Executor
      - 避免Shuffle，从根本上消除数据倾斜
      - Hint：`/*+ BROADCAST(small_table) */`

   4. **加盐拆分Join**（Join操作）：
      - 倾斜Key数据复制N份，加0~N-1前缀
      - 另一表膨胀N倍，加0~N-1前缀
      - Join后去除前缀

   5. **AQE自动优化**（Spark 3.0+）：
      - `spark.sql.adaptive.skewJoin.enabled=true`
      - 自动检测并拆分倾斜分区

   **三、过滤异常数据**：
   - 空值、默认值、异常值可能导致倾斜
   - Shuffle前先过滤无效Key

   **四、自定义Partitioner**：
   - 根据数据分布自定义分区策略
   - 将倾斜Key的数据均匀分散

   **五、采样分析**：
   ```scala
   rdd.sample(false, 0.1).map(x => (x._1, 1)).reduceByKey(_+_).collect()
   ```
   先采样找出倾斜Key，再针对性处理
51. 什么是Spark的TreeAggregate？

   **定义**：TreeAggregate是Spark中`aggregate`算子的一种优化实现，采用树形聚合策略减少Shuffle数据量。它通过多级聚合（Map端本地聚合 → 多级中间聚合 → 最终聚合）来减少网络传输。

   **工作原理**：
   1. **第一级聚合**：每个Partition内先进行本地聚合（combine）
   2. **中间级聚合**：将多个分区的聚合结果再进行聚合，形成树形结构
   3. **最终聚合**：在Driver端进行最终聚合

   **参数说明**：
   ```scala
   def treeAggregate[U](zeroValue: U)(
       seqOp: (U, T) => U,      // 分区内聚合函数
       combOp: (U, U) => U,     // 分区间聚合函数
       depth: Int = 2           // 聚合深度，默认2
   ): U
   ```

   **优势**：
   - 减少Shuffle数据量，降低网络IO
   - 减少Driver端内存压力
   - 适用于大规模数据聚合场景

   **使用场景**：全局count、sum、avg等聚合操作，特别是数据量大的情况。
52. Spark中`foreachPartition`和`foreach`的区别是什么？

   | 对比项 | foreach | foreachPartition |
   |--------|---------|-----------------|
   | 处理粒度 | 每个元素 | 每个分区（一批元素） |
   | 调用次数 | 元素数量 | 分区数量 |
   | 资源开销 | 高（每个元素一次调用） | 低（每个分区一次调用） |
   | 连接资源 | 每个元素都创建/关闭连接 | 每个分区创建/关闭一次连接 |
   | 适用场景 | 简单元素处理 | 批量写入数据库、创建连接等 |

   **示例**：
   ```scala
   // foreach: 每个元素都创建数据库连接（低效）
   rdd.foreach { record =>
     val conn = DriverManager.getConnection(url)
     conn.createStatement().execute(s"INSERT INTO table VALUES ($record)")
     conn.close()
   }
   
   // foreachPartition: 每个分区只创建一次连接（高效）
   rdd.foreachPartition { iter =>
     val conn = DriverManager.getConnection(url)
     iter.foreach { record =>
       conn.createStatement().execute(s"INSERT INTO table VALUES ($record)")
     }
     conn.close()
   }
   ```

   **建议**：涉及外部资源（数据库连接、网络请求等）时，使用`foreachPartition`以减少资源创建开销。
53. 什么是Spark的Shuffle Fetch？

   **定义**：Shuffle Fetch是Shuffle Read阶段的核心过程，指Reduce Task从各个Map Task所在的节点拉取（Fetch）Shuffle数据的过程。

   **Fetch过程**：
   1. **MapOutputTracker**：Driver维护MapOutputTracker，记录每个Map Task输出的位置和大小
   2. **BlockManager**：Reduce Task通过BlockManager获取Shuffle数据的位置信息
   3. **网络传输**：Reduce Task通过Netty从Map Task节点拉取数据
   4. **数据合并**：Reduce Task将拉取的数据合并到内存或磁盘

   **Fetch方式**：
   - **本地Fetch**：如果Reduce Task和Map Task在同一节点，直接从本地磁盘读取
   - **远程Fetch**：如果不在同一节点，通过网络从远程节点拉取

   **相关配置**：
   ```properties
   spark.shuffle.fetch.enabled=true              # 是否启用Fetch
   spark.reducer.fetchMaxBlocksInFlight=2147483647  # 单次Fetch的最大Block数
   spark.reducer.fetchMaxBytesInFlight=Long.MaxValue  # 单次Fetch的最大字节数
   ```
54. Spark中如何处理大表Join大表？

   **大表Join大表的优化策略**：

   1. **使用Sort-Merge Join**：
      - Spark默认的Join策略，适合两张大表
      - 先按Join Key排序，再合并，避免全量Shuffle
      - 配置：`spark.sql.join.preferSortMergeJoin=true`（默认）

   2. **Bucket Join（分桶Join）**：
      - 预先对两张表按Join Key分桶（Bucket）和排序
      - Join时直接匹配对应的桶，避免Shuffle
      - 配置：`spark.sql.bucketing.enabled=true`

   3. **分批Join**：
      - 将一张表拆分成多个小批次，逐批与另一张表Join
      - 适合一张表可以拆分的情况

   4. **使用Salt（加盐）解决数据倾斜**：
      - 对倾斜Key加随机前缀，拆分到多个分区
      - Join后再去除前缀合并结果

   5. **使用AQE的Skew Join优化**：
      - Spark 3.0+自动检测倾斜分区并优化
      - 配置：`spark.sql.adaptive.skewJoin.enabled=true`

   6. **使用Delta Lake / Hudi的Z-Order**：
      - 对Join Key进行Z-Order排序，加速Join

   **示例**：
   ```scala
   // Bucket Join示例
   // 建表时指定分桶
   df.write.bucketBy(100, "join_key").sortBy("join_key").saveAsTable("table1")
   df.write.bucketBy(100, "join_key").sortBy("join_key").saveAsTable("table2")
   
   // Join时自动使用Bucket Join，无需Shuffle
   spark.table("table1").join(spark.table("table2"), "join_key")
   ```
55. 什么是Spark的Shuffle Sort？

   **定义**：Shuffle Sort是Spark在Shuffle过程中对数据进行排序的机制，主要在SortShuffleManager中实现。

   **排序场景**：
   1. **需要全局排序的算子**：`sortByKey`、`sortBy`、`repartitionAndSortWithinPartitions`
   2. **Shuffle Write阶段**：SortShuffleManager在写入时会对数据进行排序，即使不需要全局排序

   **SortShuffleManager的三种Writer**：
   1. **BypassMergeSortShuffleWriter**：
      - 适用于分区数少且不需要Map端聚合的场景
      - 不排序，直接写入多个文件后合并
      - 条件：分区数 < `spark.shuffle.sort.bypassMergeThreshold`（默认200）

   2. **UnsafeShuffleWriter**：
      - 使用Tungsten的堆外内存管理
      - 适用于序列化后数据量小的场景
      - 条件：序列化后数据 < `spark.shuffle.spill.numElementsForceSpillThreshold`（默认16777216）

   3. **SortShuffleWriter**：
      - 通用Writer，支持Map端聚合
      - 使用内存缓冲区+外部排序

   **相关配置**：
   ```properties
   spark.shuffle.manager=sort  # 默认SortShuffleManager
   spark.shuffle.sort.bypassMergeThreshold=200
   ```
56. Spark中`keyBy`和`mapToPair`的区别是什么？

   **注意**：`keyBy`是Spark API，`mapToPair`是Java RDD API，两者功能类似但语言不同。

   **keyBy（Scala API）**：
   ```scala
   def keyBy[K](f: T => K): RDD[(K, T)]
   // 将每个元素转换为(Key, Value)对
   val rdd = sc.parallelize(Seq("apple", "banana", "cherry"))
   val keyed = rdd.keyBy(_.length)  // (3, "apple"), (6, "banana"), (6, "cherry")
   ```

   **mapToPair（Java API）**：
   ```java
   JavaPairRDD<K, V> mapToPair(PairFunction<T, K, V> f)
   // 将每个元素转换为Tuple2<K, V>
   JavaRDD<String> rdd = sc.parallelize(Arrays.asList("apple", "banana"));
   JavaPairRDD<Integer, String> paired = rdd.mapToPair(s -> new Tuple2<>(s.length(), s));
   ```

   **对比**：
   | 对比项 | keyBy | mapToPair |
   |--------|-------|-----------|
   | 语言 | Scala | Java |
   | 返回类型 | RDD[(K, T)] | JavaPairRDD<K, V> |
   | 转换方式 | 提取Key，Value为原元素 | 完全自定义Key和Value |
   | 灵活性 | 较低（Value固定为原元素） | 较高（Key和Value都可自定义） |
57. 什么是Spark的Shuffle Compress？

   **定义**：Shuffle Compress是指在Shuffle Write阶段对Shuffle数据进行压缩，以减少磁盘IO和网络传输量。

   **压缩位置**：
   - **Shuffle Write压缩**：Map Task写入Shuffle文件时压缩
   - **Shuffle Read压缩**：Reduce Task读取时解压（透明处理）

   **相关配置**：
   ```properties
   # 是否启用Shuffle压缩（默认true）
   spark.shuffle.compress=true
   
   # Shuffle压缩编解码器（默认lz4）
   spark.shuffle.compression.codec=lz4  # 可选：lz4, lzf, snappy, zstd
   
   # 是否压缩Shuffle Spill文件（默认true）
   spark.shuffle.spill.compress=true
   ```

   **压缩算法对比**：
   | 算法 | 压缩比 | 压缩速度 | 解压速度 |
   |------|--------|----------|----------|
   | LZ4 | 中 | 最快 | 最快 |
   | LZF | 中 | 快 | 快 |
   | Snappy | 中 | 快 | 快 |
   | ZSTD | 高 | 中 | 中 |

   **建议**：
   - 默认使用LZ4，平衡压缩比和速度
   - 磁盘IO是瓶颈时，使用ZSTD提高压缩比
   - CPU是瓶颈时，使用LZ4减少CPU开销
58. Spark中如何优化数据读取？

   **数据读取优化策略**：

   1. **使用列式存储格式**：
      - Parquet、ORC、Delta Lake等列式存储
      - 优势：列裁剪、谓词下推、压缩效率高

   2. **分区裁剪**：
      - 合理设置分区列，只读取需要的分区
      - 避免过度分区（小分区过多）

   3. **谓词下推**：
      - 在数据源端过滤数据
      - Spark SQL自动优化，也可以手动优化

   4. **列裁剪**：
      - 只读取需要的列
      - 列式存储格式效果显著

   5. **控制分区大小**：
      ```properties
      spark.sql.files.maxPartitionBytes=128MB  # 单个分区最大字节数
      spark.sql.files.openCostInBytes=4MB      # 打开文件的开销
      ```

   6. **使用缓存**：
      - 对重复读取的数据使用`cache`或`persist`
      - 合理选择存储级别

   7. **使用Delta Lake / Hudi / Iceberg**：
      - 支持Time Travel（时间旅行）
      - 支持增量查询

   8. **使用向量化读取**：
      - Spark 2.0+支持向量化读取Parquet/ORC
      - 配置：`spark.sql.parquet.enableVectorizedReader=true`

   9. **使用Data Skipping**：
      - Delta Lake/Hudi/Iceberg支持Data Skipping
      - 基于统计信息跳过不需要的文件
59. 什么是Spark的Shuffle Buffer？

   **定义**：Shuffle Buffer是Shuffle过程中用于缓存数据的内存缓冲区，用于减少磁盘IO次数。

   **Buffer类型**：
   1. **Shuffle Write Buffer**：
      - Map Task写入Shuffle数据时，先写入内存缓冲区
      - 缓冲区满后刷写到磁盘
      - 每个分区对应一个缓冲区

   2. **Shuffle Read Buffer**：
      - Reduce Task从远程节点拉取数据时，先写入内存缓冲区
      - 缓冲区满后溢写到磁盘

   **相关配置**：
   ```properties
   # Shuffle Write Buffer大小（默认32KB）
   spark.shuffle.file.buffer=32k
   
   # Shuffle Read Buffer大小（默认48MB）
   spark.reducer.maxSizeInFlight=48m
   
   # Shuffle Sort Buffer大小（默认40MB）
   spark.shuffle.sort.initialBufferFactor=0.2  # 初始缓冲区比例
   ```

   **优化建议**：
   - 内存充足时，增大Buffer大小，减少磁盘IO
   - 内存紧张时，减小Buffer大小，避免OOM
   - 监控Shuffle Spill次数，调整Buffer大小
60. Spark中`reduce`和`fold`的区别是什么？

   | 对比项 | reduce | fold |
   |--------|--------|------|
   | 初始值 | 无，使用第一个元素作为初始值 | 有，需要指定初始值 |
   | 空RDD | 抛出异常 | 返回初始值 |
   | 聚合顺序 | 不保证（分布式环境） | 不保证（分布式环境） |
   | 使用场景 | 确保RDD非空 | 允许RDD为空 |

   **示例**：
   ```scala
   val rdd = sc.parallelize(Seq(1, 2, 3, 4, 5))
   
   // reduce: 求和
   rdd.reduce(_ + _)  // 结果: 15
   
   // fold: 求和，初始值为0
   rdd.fold(0)(_ + _)  // 结果: 15
   
   // fold: 求和，初始值为10
   rdd.fold(10)(_ + _)  // 结果: 25 (10 + 1 + 2 + 3 + 4 + 5)
   
   // reduce: 空RDD会抛出异常
   sc.parallelize(Seq.empty[Int]).reduce(_ + _)  // 抛出异常
   
   // fold: 空RDD返回初始值
   sc.parallelize(Seq.empty[Int]).fold(0)(_ + _)  // 结果: 0
   ```

   **注意**：
   - `foldLeft`和`foldRight`是Scala集合的方法，保证顺序，但不是RDD的分布式操作
   - `aggregate`是`fold`的泛化版本，可以指定不同的初始值类型
61. 什么是Spark的Shuffle File？

   **定义**：Shuffle File是Shuffle过程中Map Task写入本地磁盘的数据文件，用于Reduce Task后续拉取。

   **文件类型**：
   1. **Data File（数据文件）**：
      - 存储实际的Shuffle数据
      - 文件名格式：`shuffle_{shuffleId}_{mapId}_{reduceId}.data`
      - 默认路径：`${spark.local.dir}/shuffle/`

   2. **Index File（索引文件）**：
      - 记录每个Reduce分区在Data File中的偏移量和长度
      - 文件名格式：`shuffle_{shuffleId}_{mapId}_{reduceId}.index`
      - 用于Reduce Task快速定位需要的数据

   **文件管理**：
   - 每个Map Task生成一个Data File和一个Index File
   - 文件在Task完成后保留，直到下游Stage完成
   - 使用External Shuffle Service时，文件在Executor退出后仍可访问

   **相关配置**：
   ```properties
   spark.local.dir=/tmp/spark  # Shuffle文件存储目录（可配置多个，逗号分隔）
   spark.shuffle.file.buffer=32k  # Shuffle文件写入缓冲区大小
   ```

   **清理策略**：
   - 下游Stage完成后，Shuffle文件会被异步删除
   - 应用结束后，所有Shuffle文件会被清理
   - 可通过`spark.cleaner.referenceTracking.cleanCheckpoints`控制清理行为
62. Spark中如何处理数据倾斜导致的长尾任务？

   **长尾任务现象**：
   - 绝大多数Task很快完成，少数Task运行时间极长
   - Spark UI显示Task执行时间分布极不均匀
   - 整体Job执行时间被长尾任务拖慢

   **解决方案**：

   1. **过滤异常Key**：
      ```scala
      val filteredRdd = rdd.filter(_._1 != "null_key")
      ```

   2. **增加Shuffle分区数**：
      ```properties
      spark.sql.shuffle.partitions=200  # 增大分区数
      ```

   3. **两阶段聚合（加盐）**：
      ```scala
      // 第一阶段：加随机前缀
      val salted = rdd.map { case (k, v) =>
         val prefix = Random.nextInt(10)
         (s"$prefix-$k", v)
      }.reduceByKey(_ + _)
      
      // 第二阶段：去除前缀，全局聚合
      val result = salted.map { case (k, v) =>
         val realKey = k.split("-")(1)
         (realKey, v)
      }.reduceByKey(_ + _)
      ```

   4. **Broadcast Join**：
      ```scala
      import org.apache.spark.sql.functions._
      val broadcastDf = broadcast(smallDf)
      largeDf.join(broadcastDf, "join_key")
      ```

   5. **使用AQE的Skew Join优化**：
      ```properties
      spark.sql.adaptive.enabled=true
      spark.sql.adaptive.skewJoin.enabled=true
      spark.sql.adaptive.skewJoin.skewedPartitionThresholdInBytes=256MB
      spark.sql.adaptive.skewJoin.skewedPartitionFactor=5
      ```

   6. **自定义Partitioner**：
      ```scala
      class CustomPartitioner(numParts: Int) extends Partitioner {
        override def numPartitions: Int = numParts
        override def getPartition(key: Any): Int = {
          // 根据Key分布自定义分区逻辑
          key.hashCode % numPartitions
        }
      }
      rdd.partitionBy(new CustomPartitioner(100))
      ```
63. 什么是Spark的Shuffle Index？

   **定义**：Shuffle Index是Shuffle过程中的索引文件，记录每个Reduce分区在Data File中的偏移量和长度，用于Reduce Task快速定位需要的数据。

   **索引文件结构**：
   - 每个Map Task生成一个Index File
   - Index File包含（numPartitions + 1）个Long值
   - 第i个Long值表示第i个Reduce分区的起始偏移量
   - 第i+1个Long值表示第i个Reduce分区的结束偏移量
   - 第i个Reduce分区的数据长度 = offset[i+1] - offset[i]

   **文件命名**：
   - 格式：`shuffle_{shuffleId}_{mapId}_{reduceId}.index`
   - 示例：`shuffle_0_1_0.index`（shuffleId=0, mapId=1, reduceId=0）

   **工作原理**：
   1. Map Task写入Shuffle数据时，同时更新Index File
   2. Reduce Task通过Index File快速定位需要的数据段
   3. Reduce Task只读取自己需要的分区数据，避免全量扫描

   **优势**：
   - 减少Reduce Task的数据读取量
   - 提高Shuffle Read性能
   - 支持随机访问

   **相关配置**：
   ```properties
   spark.shuffle.index.shuffleFile.enabled=true  # 是否启用索引文件（默认true）
   ```
64. Spark中`sample`和`takeSample`的区别是什么？

   | 对比项 | sample | takeSample |
   |--------|--------|------------|
   | 返回类型 | RDD[T] | Array[T] |
   | 是否Action | 否（Transformation） | 是（Action） |
   | 执行时机 | 惰性执行，需Action触发 | 立即执行 |
   | 返回结果 | 可能重复或不足 | 精确返回n个元素 |
   | 确定性 | 每次运行可能不同 | 每次运行可能不同 |
   | 数据量 | 可控制比例 | 固定数量 |

   **示例**：
   ```scala
   val rdd = sc.parallelize(1 to 100)
   
   // sample: 返回RDD，约10%的数据
   val sampled = rdd.sample(withReplacement=false, fraction=0.1)
   sampled.collect()  // 触发Action，返回约10个元素
   
   // takeSample: 返回Array，精确返回5个元素
   val taken = rdd.takeSample(withReplacement=false, num=5)
   // 立即返回5个元素
   ```

   **参数说明**：
   ```scala
   // sample
   def sample(
       withReplacement: Boolean,  // 是否放回抽样
       fraction: Double,          // 抽样比例（0-1）
       seed: Long = Utils.random.nextLong  // 随机种子
   ): RDD[T]
   
   // takeSample
   def takeSample(
       withReplacement: Boolean,  // 是否放回抽样
       num: Int,                  // 抽样数量
       seed: Long = Utils.random.nextLong  // 随机种子
   ): Array[T]
   ```

   **使用场景**：
   - `sample`：需要进一步转换处理的数据采样
   - `takeSample`：需要获取固定数量样本用于分析或测试
65. 什么是Spark的Shuffle Data？

   **定义**：Shuffle Data是Shuffle过程中在Map Task和Reduce Task之间传输的数据。

   **数据流向**：
   1. **Shuffle Write**：
      - Map Task处理数据后，按Partitioner分区
      - 数据写入本地磁盘的Shuffle Data File

   2. **Shuffle Read**：
      - Reduce Task从各个Map Task节点拉取Shuffle Data
      - 数据合并到内存或磁盘

   **数据格式**：
   - 默认使用Java序列化或Kryo序列化
   - 可配置压缩以减少传输量
   - 数据按Key-Value对组织

   **数据量控制**：
   ```properties
   # Map端预聚合，减少Shuffle数据量
   spark.shuffle.compress=true  # 压缩Shuffle数据
   
   # 控制Shuffle Write Buffer大小
   spark.shuffle.file.buffer=32k
   
   # 控制Shuffle Read Buffer大小
   spark.reducer.maxSizeInFlight=48m
   ```

   **优化建议**：
   - 使用`reduceByKey`代替`groupByKey`，减少Shuffle数据量
   - 使用Broadcast Join避免Shuffle
   - 增加Shuffle分区数，减少单个分区的数据量
   - 使用压缩减少网络传输量
66. Spark中如何优化数据写入？

   **数据写入优化策略**：

   1. **控制分区数**：
      ```scala
      // 减少输出文件数
      df.coalesce(10).write.parquet("/path/output")
      
      // 或配置Shuffle分区数
      spark.conf.set("spark.sql.shuffle.partitions", "10")
      ```

   2. **使用列式存储格式**：
      ```scala
      df.write.format("parquet").save("/path/output")
      // 或
      df.write.format("orc").save("/path/output")
      ```

   3. **启用压缩**：
      ```scala
      df.write.option("compression", "snappy").parquet("/path/output")
      // 或配置
      spark.conf.set("spark.sql.parquet.compression.codec", "snappy")
      ```

   4. **使用Bucketing**：
      ```scala
      df.write.bucketBy(100, "id").sortBy("id").saveAsTable("bucketed_table")
      ```

   5. **使用分区表**：
      ```scala
      df.write.partitionBy("date", "region").parquet("/path/output")
      // 注意：避免过度分区
      ```

   6. **使用Delta Lake / Hudi / Iceberg**：
      ```scala
      df.write.format("delta").save("/path/delta_table")
      // 支持ACID事务、Time Travel、自动Compaction
      ```

   7. **批量写入**：
      ```scala
      // 使用foreachPartition批量写入数据库
      df.foreachPartition { iter =>
        val conn = DriverManager.getConnection(url)
        val stmt = conn.prepareStatement("INSERT INTO table VALUES (?, ?)")
        iter.foreach { row =>
          stmt.setString(1, row.getAs[String]("name"))
          stmt.setInt(2, row.getAs[Int]("age"))
          stmt.addBatch()
        }
        stmt.executeBatch()
        conn.close()
      }
      ```

   8. **使用V2 Data Source**：
      ```scala
      // Spark 3.0+支持Data Source V2 API
      df.writeTo("catalog.db.table").append()
      ```
67. 什么是Spark的Shuffle Memory？

   **定义**：Shuffle Memory是Spark中用于Shuffle操作的内存区域，包括Shuffle Write和Shuffle Read阶段使用的内存。

   **内存划分**：
   - **Execution Memory（执行内存）**：用于Shuffle、Join、Sort、聚合等操作
   - **Storage Memory（存储内存）**：用于缓存RDD、广播变量等
   - 两者可以互相借用，但Execution Memory优先级更高

   **Shuffle Memory使用**：
   1. **Shuffle Write**：
      - 排序缓冲区
      - 聚合缓冲区
      - 数据序列化缓冲区

   2. **Shuffle Read**：
      - 数据拉取缓冲区
      - 排序缓冲区
      - 聚合缓冲区

   **相关配置**：
   ```properties
   # 执行内存占比（默认0.6）
   spark.memory.fraction=0.6
   
   # 执行内存中Shuffle内存占比（默认0.5）
   spark.memory.storageFraction=0.5
   
   # Shuffle Write Buffer大小
   spark.shuffle.file.buffer=32k
   
   # Shuffle Read Buffer大小
   spark.reducer.maxSizeInFlight=48m
   ```

   **优化建议**：
   - Shuffle密集型任务：增大Execution Memory占比
   - 缓存密集型任务：增大Storage Memory占比
   - 监控Shuffle Spill次数，调整内存配置
   - 使用堆外内存减少GC压力
68. Spark中`zip`和`zipWithIndex`的区别是什么？

   | 对比项 | zip | zipWithIndex |
   |--------|-----|-------------|
   | 功能 | 将两个RDD按元素位置配对 | 为每个元素添加索引 |
   | 返回类型 | RDD[(T, U)] | RDD[(T, Long)] |
   | 参数 | 需要另一个RDD | 无需参数 |
   | 分区数 | 要求两个RDD分区数相同 | 可配置分区数 |
   | 元素数量 | 要求两个RDD元素数量相同 | 任意数量 |

   **示例**：
   ```scala
   val rdd1 = sc.parallelize(Seq("a", "b", "c"))
   val rdd2 = sc.parallelize(Seq(1, 2, 3))
   
   // zip: 配对两个RDD
   rdd1.zip(rdd2).collect()
   // 结果: Array(("a", 1), ("b", 2), ("c", 3))
   
   // zipWithIndex: 添加索引
   rdd1.zipWithIndex().collect()
   // 结果: Array(("a", 0), ("b", 1), ("c", 2))
   ```

   **注意事项**：
   - `zip`要求两个RDD分区数相同，否则抛出异常
   - `zip`要求两个RDD元素数量相同，否则结果可能不完整
   - `zipWithIndex`需要一次Shuffle操作（除非RDD已分区）
   - `zipWithIndex`的索引从0开始

   **使用场景**：
   - `zip`：需要将两个相关数据集按位置配对
   - `zipWithIndex`：需要为数据添加行号或序号
69. 什么是Spark的Shuffle Disk？

   **定义**：Shuffle Disk是Shuffle过程中用于存储溢写数据的磁盘空间。当Shuffle Memory不足时，数据会溢写到磁盘。

   **溢写触发条件**：
   - Execution Memory不足，且无法借用Storage Memory
   - 单个Shuffle Write/Read缓冲区达到阈值
   - 排序数据量超过内存限制

   **磁盘使用场景**：
   1. **Shuffle Write Spill**：
      - Map Task的排序缓冲区满时，数据溢写到磁盘
      - 溢写文件最终合并为Shuffle File

   2. **Shuffle Read Spill**：
      - Reduce Task的聚合缓冲区满时，数据溢写到磁盘
      - 溢写文件用于后续外部排序

   **相关配置**：
   ```properties
   # Shuffle文件存储目录
   spark.local.dir=/tmp/spark  # 可配置多个目录，逗号分隔
   
   # Shuffle Spill阈值
   spark.shuffle.spill.numElementsForceSpillThreshold=16777216
   
   # 是否压缩Shuffle Spill文件
   spark.shuffle.spill.compress=true
   
   # Shuffle Spill压缩编解码器
   spark.io.compression.codec=lz4
   ```

   **优化建议**：
   - 配置多个`spark.local.dir`，分散磁盘IO
   - 使用SSD存储Shuffle文件
   - 增大Execution Memory，减少Spill
   - 启用压缩，减少磁盘占用
70. Spark中如何处理数据倾斜导致的Shuffle问题？

   **Shuffle阶段数据倾斜的表现**：
   - 某些Shuffle Write/Read Task处理的数据量远大于其他Task
   - Shuffle Write/Read时间分布极不均匀
   - 部分节点磁盘IO或网络带宽成为瓶颈

   **解决方案**：

   1. **调整Shuffle分区数**：
      ```properties
      spark.sql.shuffle.partitions=200  # 增大分区数
      ```

   2. **使用SortShuffleManager的Bypass模式**：
      ```properties
      spark.shuffle.manager=sort
      spark.shuffle.sort.bypassMergeThreshold=200  # 分区数小于此值时使用Bypass模式
      ```

   3. **使用Broadcast Join**：
      ```scala
      import org.apache.spark.sql.functions._
      val broadcastDf = broadcast(smallDf)
      largeDf.join(broadcastDf, "join_key")
      ```

   4. **两阶段聚合（加盐）**：
      ```scala
      // 第一阶段：加随机前缀
      val salted = rdd.map { case (k, v) =>
         val prefix = Random.nextInt(10)
         (s"$prefix-$k", v)
      }.reduceByKey(_ + _)
      
      // 第二阶段：去除前缀，全局聚合
      val result = salted.map { case (k, v) =>
         val realKey = k.split("-")(1)
         (realKey, v)
      }.reduceByKey(_ + _)
      ```

   5. **使用AQE的动态Shuffle分区合并**：
      ```properties
      spark.sql.adaptive.enabled=true
      spark.sql.adaptive.coalescePartitions.enabled=true
      spark.sql.adaptive.coalescePartitions.initialPartitionNum=200
      spark.sql.adaptive.coalescePartitions.targetSize=64MB
      ```

   6. **使用Push-based Shuffle**：
      ```properties
      spark.shuffle.push.enabled=true
      spark.shuffle.push.server.port=8020
      ```

   7. **自定义Partitioner**：
      ```scala
      class CustomPartitioner(numParts: Int) extends Partitioner {
        override def numPartitions: Int = numParts
        override def getPartition(key: Any): Int = {
          // 根据Key分布自定义分区逻辑
          key.hashCode % numPartitions
        }
      }
      rdd.partitionBy(new CustomPartitioner(100))
      ```
71. 什么是Spark的Shuffle Network？

   **定义**：Shuffle Network是Spark在Shuffle过程中用于数据传输的网络层，负责在Map Task和Reduce Task之间传输Shuffle数据。

   **网络传输机制**：
   1. **Netty框架**：Spark 1.6+使用Netty作为默认的网络传输框架
   2. **数据拉取**：Reduce Task通过Netty从Map Task节点拉取数据
   3. **连接池**：使用连接池复用TCP连接，减少连接建立开销
   4. **零拷贝**：使用Netty的零拷贝技术，减少内存拷贝

   **网络优化配置**：
   ```properties
   # Netty配置
   spark.shuffle.io.mode=netty  # 使用Netty（默认）
   spark.shuffle.io.numConnectionsPerPeer=1  # 每个对等节点的连接数
   spark.shuffle.io.connectionTimeout=60s  # 连接超时时间
   spark.shuffle.io.backLog=32  # 连接队列长度
   
   # Fetch配置
   spark.reducer.fetchMaxBlocksInFlight=2147483647  # 单次Fetch的最大Block数
   spark.reducer.fetchMaxBytesInFlight=Long.MaxValue  # 单次Fetch的最大字节数
   ```

   **网络优化建议**：
   - 增大`fetchMaxBytesInFlight`，减少网络往返次数
   - 使用万兆网络，提升带宽
   - 启用压缩，减少网络传输量
   - 使用机架感知，减少跨机架传输
72. Spark中`join`和`cogroup`的区别是什么？

   | 对比项 | join | cogroup |
   |--------|------|---------|
   | 返回类型 | RDD[(K, (V, W))] | RDD[(K, (Iterable[V], Iterable[W]))] |
   | 数据处理 | 笛卡尔积后过滤 | 分组后保留所有值 |
   | 内存占用 | 较低 | 较高（需缓存所有值） |
   | 灵活性 | 较低 | 较高 |
   | 使用场景 | 简单Join | 复杂Join、多表Join |

   **示例**：
   ```scala
   val rdd1 = sc.parallelize(Seq(("a", 1), ("b", 2), ("c", 3)))
   val rdd2 = sc.parallelize(Seq(("a", 4), ("a", 5), ("b", 6)))
   
   // join: 笛卡尔积
   rdd1.join(rdd2).collect()
   // 结果: Array(("a", (1, 4)), ("a", (1, 5)), ("b", (2, 6)))
   
   // cogroup: 分组
   rdd1.cogroup(rdd2).collect()
   // 结果: Array(("a", (CompactBuffer(1), CompactBuffer(4, 5))),
   //             ("b", (CompactBuffer(2), CompactBuffer(6))),
   //             ("c", (CompactBuffer(3), CompactBuffer())))
   ```

   **使用场景**：
   - `join`：简单的内连接、外连接
   - `cogroup`：需要访问所有值的复杂Join、多表Join、自定义Join逻辑
73. 什么是Spark的Shuffle Service？

   **定义**：Shuffle Service是Spark提供的独立服务，负责管理Shuffle文件的读取和写入，与Executor解耦。

   **两种Shuffle Service**：
   1. **External Shuffle Service**：
      - 独立于Executor运行的服务
      - 通常以YARN Auxiliary Service形式部署
      - 负责管理Shuffle文件的读取

   2. **Remote Shuffle Service**：
      - Spark 3.0+引入的远程Shuffle服务
      - 支持将Shuffle数据存储到远程存储（如S3、HDFS）
      - 支持Push-based Shuffle

   **External Shuffle Service的作用**：
   1. **Executor解耦**：Executor退出后，Shuffle文件仍可被访问
   2. **动态资源分配**：配合Dynamic Allocation使用
   3. **减少资源占用**：Executor不需要持续运行

   **配置方式**：
   ```properties
   # Spark端配置
   spark.shuffle.service.enabled=true
   spark.shuffle.service.port=7337
   
   # YARN端配置（yarn-site.xml）
   yarn.nodemanager.aux-services=spark_shuffle
   yarn.nodemanager.aux-services.spark_shuffle.class=org.apache.spark.network.yarn.YarnShuffleService
   ```
74. Spark中如何优化Shuffle操作？

   **Shuffle优化策略**：

   1. **减少Shuffle次数**：
      ```scala
      // 不好的方式：多次Shuffle
      val rdd1 = rdd.groupByKey()
      val rdd2 = rdd1.reduceByKey(_ + _)
      
      // 好的方式：一次Shuffle
      val rdd3 = rdd.reduceByKey(_ + _)
      ```

   2. **使用Broadcast Join**：
      ```scala
      import org.apache.spark.sql.functions._
      val broadcastDf = broadcast(smallDf)
      largeDf.join(broadcastDf, "join_key")
      ```

   3. **调整Shuffle分区数**：
      ```properties
      spark.sql.shuffle.partitions=200
      ```

   4. **使用SortShuffleManager**：
      ```properties
      spark.shuffle.manager=sort
      ```

   5. **启用压缩**：
      ```properties
      spark.shuffle.compress=true
      spark.shuffle.compression.codec=lz4
      spark.shuffle.spill.compress=true
      ```

   6. **使用External Shuffle Service**：
      ```properties
      spark.shuffle.service.enabled=true
      ```

   7. **使用Push-based Shuffle（Spark 3.2+）**：
      ```properties
      spark.shuffle.push.enabled=true
      ```

   8. **使用AQE优化**：
      ```properties
      spark.sql.adaptive.enabled=true
      spark.sql.adaptive.coalescePartitions.enabled=true
      spark.sql.adaptive.skewJoin.enabled=true
      ```

   9. **优化网络配置**：
      ```properties
      spark.reducer.maxSizeInFlight=48m
      spark.reducer.fetchMaxBlocksInFlight=2147483647
      ```
75. 什么是Spark的Shuffle Partition？

   **定义**：Shuffle Partition是Shuffle过程中数据分区的最小单位，每个Shuffle Partition对应一个Reduce Task。

   **分区数量**：
   - RDD API：通过`repartition`、`partitionBy`等算子指定
   - Spark SQL：通过`spark.sql.shuffle.partitions`配置（默认200）

   **分区数的影响**：
   - **分区数过少**：
      - 单个Task处理数据量大，执行时间长
      - 容易OOM
      - 并行度低
   - **分区数过多**：
      - Task调度开销大
      - 小文件问题
      - 网络传输开销大

   **分区数选择原则**：
   - 每个分区数据量在128MB-256MB之间
   - 分区数 ≈ 总数据量 / 单个分区数据量
   - 考虑集群资源（Executor数量 × 每个Executor的Core数）

   **相关配置**：
   ```properties
   # Spark SQL默认分区数
   spark.sql.shuffle.partitions=200
   
   # AQE动态合并分区
   spark.sql.adaptive.enabled=true
   spark.sql.adaptive.coalescePartitions.enabled=true
   spark.sql.adaptive.coalescePartitions.targetSize=64MB
   ```
76. Spark中`sortByKey`和`sortBy`的区别是什么？

   | 对比项 | sortByKey | sortBy |
   |--------|-----------|--------|
   | 适用对象 | PairRDD[(K, V)] | 任意RDD[T] |
   | 排序依据 | Key | 自定义排序函数 |
   | 返回类型 | RDD[(K, V)] | RDD[T] |
   | 全局排序 | 支持（numPartitions=1） | 支持（numPartitions=1） |
   | 分区内排序 | 支持 | 支持 |

   **示例**：
   ```scala
   // sortByKey: 按Key排序
   val rdd1 = sc.parallelize(Seq(("b", 2), ("a", 1), ("c", 3)))
   rdd1.sortByKey().collect()
   // 结果: Array(("a", 1), ("b", 2), ("c", 3))
   
   // sortBy: 按自定义函数排序
   val rdd2 = sc.parallelize(Seq(("b", 2), ("a", 1), ("c", 3)))
   rdd2.sortBy(_._2).collect()
   // 结果: Array(("a", 1), ("b", 2), ("c", 3))
   
   // 全局排序
   rdd1.sortByKey(ascending=true, numPartitions=1).collect()
   ```

   **使用场景**：
   - `sortByKey`：PairRDD按Key排序
   - `sortBy`：任意RDD按自定义规则排序
77. 什么是Spark的Shuffle Handler？

   **定义**：Shuffle Handler是Shuffle Service的核心组件，负责处理Shuffle文件的读写请求。

   **Handler类型**：
   1. **ExternalShuffleHandler**：
      - 处理External Shuffle Service的请求
      - 负责读取本地Shuffle文件
      - 响应Reduce Task的Fetch请求

   2. **RemoteShuffleHandler**：
      - 处理Remote Shuffle Service的请求
      - 支持Push-based Shuffle
      - 支持远程存储（S3、HDFS）

   **工作流程**：
   1. Reduce Task向Shuffle Handler发送Fetch请求
   2. Shuffle Handler查找本地Shuffle文件
   3. Shuffle Handler读取数据并通过网络返回
   4. Reduce Task接收数据并处理

   **相关配置**：
   ```properties
   # External Shuffle Service配置
   spark.shuffle.service.enabled=true
   spark.shuffle.service.port=7337
   
   # Remote Shuffle Service配置
   spark.shuffle.service.enabled=true
   spark.shuffle.service.remote.enabled=true
   ```
78. Spark中如何处理数据倾斜导致的内存问题？

   **内存问题表现**：
   - 某些Task出现OOM
   - GC时间过长
   - Executor内存不足

   **解决方案**：

   1. **增大Executor内存**：
      ```properties
      spark.executor.memory=8g
      spark.memory.fraction=0.6
      spark.memory.storageFraction=0.5
      ```

   2. **使用堆外内存**：
      ```properties
      spark.memory.offHeap.enabled=true
      spark.memory.offHeap.size=2g
      ```

   3. **调整存储级别**：
      ```scala
      // 使用序列化存储
      rdd.persist(StorageLevel.MEMORY_ONLY_SER)
      ```

   4. **减少Shuffle数据量**：
      ```scala
      // 使用reduceByKey代替groupByKey
      rdd.reduceByKey(_ + _)
      ```

   5. **使用Broadcast Join**：
      ```scala
      import org.apache.spark.sql.functions._
      val broadcastDf = broadcast(smallDf)
      largeDf.join(broadcastDf, "join_key")
      ```

   6. **使用AQE的Skew Join优化**：
      ```properties
      spark.sql.adaptive.enabled=true
      spark.sql.adaptive.skewJoin.enabled=true
      ```

   7. **使用两阶段聚合（加盐）**：
      ```scala
      // 第一阶段：加随机前缀
      val salted = rdd.map { case (k, v) =>
         val prefix = Random.nextInt(10)
         (s"$prefix-$k", v)
      }.reduceByKey(_ + _)
      
      // 第二阶段：去除前缀，全局聚合
      val result = salted.map { case (k, v) =>
         val realKey = k.split("-")(1)
         (realKey, v)
      }.reduceByKey(_ + _)
      ```

   8. **优化GC参数**：
      ```properties
      spark.executor.extraJavaOptions="-XX:+UseG1GC -XX:MaxGCPauseMillis=200"
      ```
79. 什么是Spark的Shuffle Manager？

   **定义**：Shuffle Manager是Spark中负责管理Shuffle操作的组件，决定Shuffle数据的写入和读取方式。

   **Shuffle Manager类型**：

   1. **SortShuffleManager（默认）**：
      - Spark 1.2+引入，Spark 2.0+成为默认
      - 支持Map端聚合
      - 使用排序缓冲区+外部排序
      - 三种Writer：BypassMergeSortShuffleWriter、UnsafeShuffleWriter、SortShuffleWriter

   2. **HashShuffleManager（已废弃）**：
      - Spark 1.2之前使用
      - 为每个Reduce分区创建一个文件
      - 文件数 = Map Task数 × Reduce分区数
      - 文件数过多，性能差

   3. **Tungsten-SortShuffleManager**：
      - Spark 1.4引入，使用Tungsten优化
      - 使用堆外内存和Unsafe API
      - 已合并到SortShuffleManager

   **配置方式**：
   ```properties
   spark.shuffle.manager=sort  # 默认SortShuffleManager
   ```

   **SortShuffleManager的优势**：
   - 文件数可控（Map Task数 × 2）
   - 支持Map端聚合
   - 支持排序
   - 内存使用更高效
80. Spark中`groupByKey`和`reduceByKey`的性能差异是什么？

   **核心差异**：
   - `groupByKey`：无Map端预聚合，所有数据全量Shuffle
   - `reduceByKey`：有Map端预聚合（combine），减少Shuffle数据量

   **性能对比**：

   | 对比项 | groupByKey | reduceByKey |
   |--------|------------|-------------|
   | Map端预聚合 | 无 | 有 |
   | Shuffle数据量 | 大（全量数据） | 小（聚合后数据） |
   | 网络传输 | 大 | 小 |
   | 磁盘IO | 大 | 小 |
   | 内存占用 | 高（需缓存所有值） | 低 |
   | 执行时间 | 长 | 短 |

   **示例**：
   ```scala
   val rdd = sc.parallelize(Seq(("a", 1), ("a", 2), ("b", 3), ("b", 4)))
   
   // groupByKey: 无预聚合，Shuffle数据量大
   rdd.groupByKey().mapValues(_.sum).collect()
   
   // reduceByKey: 有预聚合，Shuffle数据量小
   rdd.reduceByKey(_ + _).collect()
   ```

   **建议**：
   - 需要聚合操作时，优先使用`reduceByKey`、`aggregateByKey`等带预聚合的算子
   - 只有确实需要获取每个Key的所有值时才使用`groupByKey`
   - 数据量大时，`reduceByKey`的性能优势更明显
81. 什么是Spark的Shuffle Writer？

   **定义**：Shuffle Writer是Shuffle Write阶段的核心组件，负责将Map Task的输出数据写入本地磁盘。

   **SortShuffleManager的三种Writer**：

   1. **BypassMergeSortShuffleWriter**：
      - 适用于分区数少且不需要Map端聚合的场景
      - 不排序，直接写入多个文件后合并
      - 条件：分区数小于spark.shuffle.sort.bypassMergeThreshold（默认200）
      - 优势：避免排序开销

   2. **UnsafeShuffleWriter**：
      - 使用Tungsten的堆外内存管理
      - 适用于序列化后数据量小的场景
      - 条件：序列化后数据小于spark.shuffle.spill.numElementsForceSpillThreshold（默认16777216）
      - 优势：内存占用低，GC压力小

   3. **SortShuffleWriter**：
      - 通用Writer，支持Map端聚合
      - 使用内存缓冲区+外部排序
      - 适用于大多数场景
      - 优势：功能全面，支持聚合和排序

   **工作流程**：
   1. 数据写入内存缓冲区
   2. 缓冲区满时溢写到磁盘
   3. 最终合并所有溢写文件
   4. 生成Index File记录分区偏移量
82. Spark中如何优化数据聚合？

   **数据聚合优化策略**：

   1. **使用带预聚合的算子**：
      - 好的方式：使用reduceByKey（有预聚合）
      - 不好的方式：使用groupByKey（无预聚合）

   2. **使用aggregateByKey**：
      - 更灵活的聚合，支持不同的初始值和聚合函数
      - 示例：rdd.aggregateByKey(0)(_ + _, _ + _)

   3. **使用treeAggregate**：
      - 树形聚合，减少Shuffle数据量
      - 示例：rdd.treeAggregate(0)(_ + _, _ + _, depth=2)

   4. **调整Shuffle分区数**：
      - 配置：spark.sql.shuffle.partitions=200

   5. **使用AQE优化**：
      - 配置：spark.sql.adaptive.enabled=true
      - 配置：spark.sql.adaptive.coalescePartitions.enabled=true

   6. **使用DataFrame/Dataset**：
      - 使用Catalyst优化器
      - 示例：df.groupBy("key").agg(sum("value"))

   7. **使用自定义聚合函数（UDAF）**：
      - Spark SQL中定义UDAF
      - 示例：spark.udf.register("myAgg", new MyUDAF)
      - 查询：SELECT key, myAgg(value) FROM table GROUP BY key
83. 什么是Spark的Shuffle Reader？

   **定义**：Shuffle Reader是Shuffle Read阶段的核心组件，负责从各个Map Task节点拉取Shuffle数据。

   **工作流程**：
   1. **获取位置信息**：通过MapOutputTracker获取Shuffle数据的位置
   2. **拉取数据**：通过Netty从Map Task节点拉取数据
   3. **数据合并**：将拉取的数据合并到内存或磁盘
   4. **排序/聚合**：根据需要进行排序或聚合操作

   **Fetch方式**：
   - **本地Fetch**：如果Reduce Task和Map Task在同一节点，直接从本地磁盘读取
   - **远程Fetch**：如果不在同一节点，通过网络从远程节点拉取

   **相关配置**：
   - spark.reducer.maxSizeInFlight：Shuffle Read Buffer大小（默认48m）
   - spark.reducer.fetchMaxBlocksInFlight：单次Fetch的最大Block数（默认2147483647）
   - spark.reducer.fetchMaxBytesInFlight：单次Fetch的最大字节数（默认Long.MaxValue）

   **优化建议**：
   - 增大maxSizeInFlight，减少网络往返次数
   - 使用External Shuffle Service，避免Executor退出后数据不可用
   - 启用压缩，减少网络传输量
84. Spark中如何处理数据倾斜导致的网络问题？

   **网络问题表现**：
   - 某些节点网络带宽成为瓶颈
   - Shuffle Fetch时间过长
   - 网络拥塞

   **解决方案**：

   1. **使用Broadcast Join**：
      - 示例：import org.apache.spark.sql.functions._
      - 示例：val broadcastDf = broadcast(smallDf)
      - 示例：largeDf.join(broadcastDf, "join_key")

   2. **增加Shuffle分区数**：
      - 配置：spark.sql.shuffle.partitions=200

   3. **使用两阶段聚合（加盐）**：
      - 第一阶段：加随机前缀，局部聚合
      - 第二阶段：去除前缀，全局聚合

   4. **使用AQE的Skew Join优化**：
      - 配置：spark.sql.adaptive.enabled=true
      - 配置：spark.sql.adaptive.skewJoin.enabled=true

   5. **优化网络配置**：
      - spark.reducer.maxSizeInFlight=48m
      - spark.reducer.fetchMaxBlocksInFlight=2147483647
      - spark.reducer.fetchMaxBytesInFlight=Long.MaxValue

   6. **启用压缩**：
      - spark.shuffle.compress=true
      - spark.shuffle.compression.codec=lz4

   7. **使用Push-based Shuffle（Spark 3.2+）**：
      - 配置：spark.shuffle.push.enabled=true
85. 什么是Spark的Shuffle Block？

   **定义**：Shuffle Block是Shuffle数据的最小存储单元，每个Shuffle Block对应一个Shuffle Partition的数据。

   **Block结构**：
   - 每个Map Task为每个Reduce Partition生成一个Shuffle Block
   - Block ID格式：shuffle_{shuffleId}_{mapId}_{reduceId}
   - Block存储在Shuffle File中，通过Index File定位

   **Block管理**：
   - BlockManager负责管理Shuffle Block
   - BlockManager在Driver和Executor上运行
   - BlockManager维护Block的元数据（位置、大小等）

   **Block传输**：
   - Reduce Task通过BlockManager获取Shuffle Block的位置
   - 通过Netty从Map Task节点拉取Block数据
   - 支持本地和远程拉取

   **相关配置**：
   - spark.sql.adaptive.maxShufflePartitionCount：最大Shuffle分区数（默认2147483647）
   - spark.sql.adaptive.minShufflePartitionCount：最小Shuffle分区数（默认1）
86. Spark中`mapValues`和`flatMapValues`的区别是什么？

   | 对比项 | mapValues | flatMapValues |
   |--------|-----------|---------------|
   | 输入输出关系 | 一对一：每个Value映射为一个Value | 一对多：每个Value映射为0到多个Value |
   | 返回类型 | RDD[(K, V)] | RDD[(K, U)]（展平） |
   | 输出元素数量 | 与输入相同 | 可能多于或少于输入 |
   | 空值处理 | 不能过滤元素 | 可以通过返回空集合过滤元素 |

   **示例**：
   - 输入：Seq(("a", "1 2"), ("b", "3 4 5"))
   - mapValues结果：Array(("a", Array("1", "2")), ("b", Array("3", "4", "5")))
   - flatMapValues结果：Array(("a", "1"), ("a", "2"), ("b", "3"), ("b", "4"), ("b", "5"))

   **使用场景**：
   - `mapValues`：对Value进行简单转换
   - `flatMapValues`：需要展开Value或过滤某些元素
87. 什么是Spark的Shuffle Segment？

   **定义**：Shuffle Segment是Shuffle File中的数据段，对应一个Reduce Partition的数据范围。

   **Segment结构**：
   - 每个Reduce Partition对应一个Segment
   - Segment由Index File中的偏移量和长度定义
   - Segment包含该Partition的所有数据

   **Segment定位**：
   - Index File记录每个Segment的起始偏移量和结束偏移量
   - Reduce Task通过Index File快速定位需要的Segment
   - 避免全量扫描Shuffle File

   **Segment优势**：
   - 减少Reduce Task的数据读取量
   - 提高Shuffle Read性能
   - 支持随机访问

   **相关配置**：
   - spark.shuffle.index.shuffleFile.enabled：是否启用索引文件（默认true）
88. Spark中如何优化数据过滤？

   **数据过滤优化策略**：

   1. **使用谓词下推**：
      - Spark SQL自动优化，在数据源端过滤
      - 示例：SELECT * FROM table WHERE date = "2023-01-01" AND status = "active"

   2. **尽早过滤**：
      - 好的方式：先过滤再转换
      - 不好的方式：先转换再过滤

   3. **使用列裁剪**：
      - 只读取需要的列
      - 示例：SELECT name, age FROM users WHERE age > 20

   4. **使用分区裁剪**：
      - 只读取需要的分区
      - 示例：SELECT * FROM partitioned_table WHERE date = "2023-01-01"

   5. **使用布隆过滤器**：
      - 适用于大量数据过滤
      - 减少不必要的数据传输

   6. **使用Data Skipping**：
      - Delta Lake/Hudi/Iceberg支持
      - 基于统计信息跳过不需要的文件

   7. **使用索引**：
      - Delta Lake支持索引
      - 加速查询过滤
89. 什么是Spark的Shuffle Stream？

   **定义**：Shuffle Stream是Shuffle过程中数据传输的流式通道，负责在Map Task和Reduce Task之间传输数据。

   **Stream类型**：
   1. **Write Stream**：
      - Map Task将数据写入Shuffle Stream
      - Stream缓冲区满时刷写到磁盘

   2. **Read Stream**：
      - Reduce Task从Shuffle Stream读取数据
      - Stream从多个Map Task节点拉取数据

   **Stream特性**：
   - 使用Netty框架实现
   - 支持零拷贝技术
   - 支持压缩
   - 支持连接池复用

   **相关配置**：
   - spark.shuffle.io.mode：使用Netty（默认）
   - spark.shuffle.io.numConnectionsPerPeer：每个对等节点的连接数（默认1）
   - spark.shuffle.io.connectionTimeout：连接超时时间（默认60s）
   - spark.shuffle.file.buffer：Shuffle文件写入缓冲区大小（默认32k）
   - spark.reducer.maxSizeInFlight：Shuffle Read Buffer大小（默认48m）
90. Spark中如何处理数据倾斜导致的磁盘问题？

   **磁盘问题表现**：
   - 某些节点磁盘IO成为瓶颈
   - Shuffle Spill频繁
   - 磁盘空间不足

   **解决方案**：

   1. **增大内存，减少Spill**：
      - spark.executor.memory=8g
      - spark.memory.fraction=0.6
      - spark.memory.storageFraction=0.5

   2. **配置多个Shuffle目录**：
      - spark.local.dir=/mnt/disk1/spark,/mnt/disk2/spark,/mnt/disk3/spark

   3. **使用SSD存储Shuffle文件**：
      - spark.local.dir=/ssd/spark

   4. **启用压缩**：
      - spark.shuffle.compress=true
      - spark.shuffle.compression.codec=lz4
      - spark.shuffle.spill.compress=true

   5. **使用Broadcast Join**：
      - 避免Shuffle，减少磁盘IO

   6. **使用AQE的Skew Join优化**：
      - spark.sql.adaptive.enabled=true
      - spark.sql.adaptive.skewJoin.enabled=true

   7. **使用两阶段聚合（加盐）**：
      - 第一阶段：加随机前缀，局部聚合
      - 第二阶段：去除前缀，全局聚合

   8. **调整Shuffle分区数**：
      - spark.sql.shuffle.partitions=200
91. 什么是Spark的Shuffle Buffer Size？

   **定义**：Shuffle Buffer Size是Shuffle过程中内存缓冲区的大小，用于减少磁盘IO次数。

   **Buffer类型**：
   1. **Shuffle Write Buffer**：
      - Map Task写入Shuffle数据时使用
      - 配置：spark.shuffle.file.buffer（默认32k）

   2. **Shuffle Read Buffer**：
      - Reduce Task拉取Shuffle数据时使用
      - 配置：spark.reducer.maxSizeInFlight（默认48m）

   3. **Shuffle Sort Buffer**：
      - 排序操作时使用
      - 配置：spark.shuffle.sort.initialBufferFactor（默认0.2）

   **优化建议**：
   - 内存充足时，增大Buffer大小，减少磁盘IO
   - 内存紧张时，减小Buffer大小，避免OOM
   - 监控Shuffle Spill次数，调整Buffer大小
92. Spark中`persist`和`checkpoint`的使用场景是什么？

   **persist使用场景**：
   - 数据需要多次使用时
   - 迭代式算法（如机器学习）
   - 需要快速访问中间结果
   - 数据量不大，可以放入内存

   **checkpoint使用场景**：
   - 血缘链过长，容错恢复成本高
   - 需要长期保存中间结果
   - 需要截断血缘关系
   - 关键计算节点的结果需要持久化

   **对比**：
   | 对比项 | persist | checkpoint |
   |--------|---------|-----------|
   | 存储位置 | 内存/本地磁盘 | HDFS等可靠存储 |
   | 血缘关系 | 保留 | 截断 |
   | 持久性 | 临时 | 持久 |
   | 容错性 | 低 | 高 |

   **最佳实践**：
   - 先persist再checkpoint，避免重新计算
   - 重复使用的数据用persist
   - 血缘链长用checkpoint
93. 什么是Spark的Shuffle Memory Fraction？

   **定义**：Shuffle Memory Fraction是Spark中用于Shuffle操作的内存占比配置。

   **内存划分**：
   - spark.memory.fraction：执行内存占比（默认0.6）
   - spark.memory.storageFraction：存储内存占比（默认0.5）

   **计算方式**：
   - Execution Memory = spark.executor.memory * spark.memory.fraction
   - Storage Memory = spark.executor.memory * spark.memory.fraction * spark.memory.storageFraction

   **动态占用**：
   - Execution和Storage内存可以互相借用
   - Execution Memory优先级更高

   **优化建议**：
   - Shuffle密集型：增大spark.memory.fraction
   - 缓存密集型：增大spark.memory.storageFraction
   - 监控内存使用，动态调整
94. Spark中如何优化数据转换？

   **数据转换优化策略**：

   1. **使用DataFrame/Dataset**：
      - 利用Catalyst优化器
      - 支持代码生成

   2. **减少Shuffle次数**：
      - 合并多个Shuffle操作
      - 使用带预聚合的算子

   3. **使用向量化操作**：
      - Spark SQL支持向量化
      - 配置：spark.sql.parquet.enableVectorizedReader=true

   4. **使用高效的数据结构**：
      - 使用原生类型而非包装类型
      - 使用Kryo序列化

   5. **使用广播变量**：
      - 减少数据传输
      - 优化Join操作

   6. **使用缓存**：
      - 重复使用的数据缓存
      - 合理选择存储级别

   7. **使用AQE优化**：
      - spark.sql.adaptive.enabled=true
      - 运行时动态优化
95. 什么是Spark的Shuffle Disk Fraction？

   **注意**：Spark中没有名为Shuffle Disk Fraction的配置项。可能是指以下相关配置：

   **相关配置**：
   1. **spark.memory.fraction**：
      - 执行内存占比（默认0.6）
      - 剩余内存可用于Shuffle Spill

   2. **spark.memory.storageFraction**：
      - 存储内存占比（默认0.5）
      - 影响Storage和Execution内存分配

   3. **spark.shuffle.spill.numElementsForceSpillThreshold**：
      - 强制Spill的元素数量阈值（默认16777216）

   **Shuffle Disk使用**：
   - Execution Memory不足时，数据溢写到磁盘
   - 溢写数据存储在spark.local.dir配置的目录
   - 可配置多个目录分散IO
96. Spark中如何处理数据倾斜导致的CPU问题？

   **CPU问题表现**：
   - 某些Task CPU使用率过高
   - CPU成为瓶颈
   - 任务执行时间不均匀

   **解决方案**：

   1. **使用Broadcast Join**：
      - 避免Shuffle，减少CPU计算量

   2. **使用AQE的Skew Join优化**：
      - spark.sql.adaptive.enabled=true
      - spark.sql.adaptive.skewJoin.enabled=true

   3. **使用两阶段聚合（加盐）**：
      - 分散计算压力

   4. **增加Shuffle分区数**：
      - spark.sql.shuffle.partitions=200

   5. **使用向量化操作**：
      - spark.sql.parquet.enableVectorizedReader=true

   6. **使用代码生成**：
      - spark.sql.codegen.wholeStage=true

   7. **优化序列化**：
      - 使用Kryo序列化
      - spark.serializer=org.apache.spark.serializer.KryoSerializer
97. 什么是Spark的Shuffle Compress Codec？

   **定义**：Shuffle Compress Codec是Shuffle数据压缩使用的编解码器。

   **支持的编解码器**：
   1. **LZ4**（默认）：
      - 压缩速度最快
      - 压缩比中等
      - 解压速度最快

   2. **LZF**：
      - 压缩速度快
      - 压缩比中等
      - 解压速度快

   3. **Snappy**：
      - 压缩速度快
      - 压缩比中等
      - 解压速度快

   4. **ZSTD**：
      - 压缩比最高
      - 压缩速度中等
      - 解压速度中等

   **配置方式**：
   - spark.shuffle.compression.codec=lz4
   - spark.io.compression.codec=lz4

   **选择建议**：
   - 默认使用LZ4
   - 磁盘IO瓶颈时用ZSTD
   - CPU瓶颈时用LZ4
98. Spark中如何优化数据序列化？

   **序列化优化策略**：

   1. **使用Kryo序列化**：
      - spark.serializer=org.apache.spark.serializer.KryoSerializer
      - 比Java序列化快10倍
      - 比Java序列化紧凑2-5倍

   2. **注册Kryo类**：
      - spark.kryo.registrationRequired=true
      - spark.kryo.classesToRegister=class1,class2

   3. **使用原生类型**：
      - 避免使用包装类型
      - 使用Int而非Integer

   4. **使用DataFrame/Dataset**：
      - 使用Tungsten的二进制格式
      - 自动优化序列化

   5. **使用序列化存储**：
      - rdd.persist(StorageLevel.MEMORY_ONLY_SER)

   6. **避免闭包捕获大对象**：
      - 减少闭包序列化开销

   7. **使用广播变量**：
      - 避免重复序列化大对象
99. 什么是Spark的Shuffle Fetch Buffer？

   **定义**：Shuffle Fetch Buffer是Shuffle Read阶段用于缓存拉取数据的内存缓冲区。

   **相关配置**：
   1. **spark.reducer.maxSizeInFlight**：
      - Shuffle Read Buffer大小（默认48m）
      - 控制单次Fetch的最大数据量

   2. **spark.reducer.fetchMaxBlocksInFlight**：
      - 单次Fetch的最大Block数（默认2147483647）

   3. **spark.reducer.fetchMaxBytesInFlight**：
      - 单次Fetch的最大字节数（默认Long.MaxValue）

   **工作原理**：
   - Reduce Task从Map Task节点拉取数据
   - 数据先写入Fetch Buffer
   - Buffer满时溢写到磁盘
   - 最终合并所有数据

   **优化建议**：
   - 增大maxSizeInFlight，减少网络往返次数
   - 监控Shuffle Spill次数，调整Buffer大小
   - 内存充足时增大Buffer，减少磁盘IO
100. Spark中如何处理数据倾斜导致的GC问题？

   **GC问题表现**：
   - GC时间过长
   - Full GC频繁
   - OOM错误

   **解决方案**：

   1. **增大Executor内存**：
      - spark.executor.memory=8g

   2. **使用堆外内存**：
      - spark.memory.offHeap.enabled=true
      - spark.memory.offHeap.size=2g

   3. **调整内存比例**：
      - spark.memory.fraction=0.6
      - spark.memory.storageFraction=0.5

   4. **使用序列化存储**：
      - rdd.persist(StorageLevel.MEMORY_ONLY_SER)

   5. **使用Kryo序列化**：
      - spark.serializer=org.apache.spark.serializer.KryoSerializer

   6. **优化GC参数**：
      - spark.executor.extraJavaOptions=-XX:+UseG1GC
      - spark.executor.extraJavaOptions=-XX:MaxGCPauseMillis=200

   7. **减少Shuffle数据量**：
      - 使用reduceByKey代替groupByKey
      - 使用Broadcast Join

   8. **使用AQE优化**：
      - spark.sql.adaptive.enabled=true
      - spark.sql.adaptive.skewJoin.enabled=true
