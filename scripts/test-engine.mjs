// 桌面业务用例快照（2026-10-15）及手机端补充回归，不写入真实应用数据。
// 运行：node scripts/test-engine.mjs；TypeScript 可由 TYPESCRIPT_PATH 指定。
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
const project = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const require = createRequire(import.meta.url);
let ts;
const locations = [process.env.TYPESCRIPT_PATH, 'typescript', path.join(project, '../Planer/node_modules/typescript'),
  'D:/Software/DevEco Studio/tools/node_modules/typescript',
  'D:/Software/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'];
for (const location of locations.filter(Boolean)) {
  try { ts = require(location); break; } catch { /* 尝试下一个已安装工具链 */ }
}
if (!ts) throw new Error('请安装 TypeScript 或设置 TYPESCRIPT_PATH 指向已有 TypeScript 模块。');
const cache = new Map();
function load(name) {
  if (cache.has(name)) return cache.get(name);
  const source = readFileSync(path.join(project, 'entry/src/main/ets/model', `${name}.ets`), 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, reportDiagnostics: true });
  const errors = (output.diagnostics || []).filter(diagnostic => diagnostic.category === ts.DiagnosticCategory.Error);
  if (errors.length) throw new Error(ts.formatDiagnosticsWithColorAndContext(errors, { getCurrentDirectory: () => project, getCanonicalFileName: file => file, getNewLine: () => '\n' }));
  const module = { exports: {} };
  vm.runInThisContext(`(function(require,module,exports){${output.outputText}\n})`, { filename: `${name}.ets` })(
    request => load(path.basename(request)), module, module.exports);
  cache.set(name, module.exports);
  return module.exports;
}
const model = load('PlanerModel');
const engine = load('PlanerEngine');
const { freshData, normalizeData } = engine;
// 只适配动作包装形式，所有待验证规则由真实 ArkTS 引擎执行。
function reducer(state, original) {
  const data = state instanceof model.AppData ? state : normalizeData(state);
  const action = Object.assign(new model.AppAction(original.type), original);
  if (original.type === 'SET_SETTINGS') {
    action.settings = Object.assign(data.settings.clone(), original.patch);
  }
  if (original.type === 'REORDER') action.toIndex = original.to;
  return engine.reduce(data, action);
}
// ---- 工具 ----
let passed = 0;
let failed = 0;
function assert(cond, msg) {
  if (cond) {
    passed++;
    console.log(`  ✓ ${msg}`);
  } else {
    failed++;
    console.error(`  ✗ ${msg}`);
  }
}

function fresh() {
  return {
    version: 1,
    currentDate: "2026-08-24",
    todayTasks: [],
    futureTasks: [],
    groups: [],
    history: [],
    settings: { autoNumber: true, showGroups: false },
  };
}

// ---- 测试用例 ----
console.log("1) 添加日程");
{
  let s = fresh();
  s = reducer(s, { type: "ADD_TASK", section: "today", text: "买菜" });
  s = reducer(s, { type: "ADD_TASK", section: "today", text: "写报告" });
  assert(s.todayTasks.length === 2, "当日日程添加两条");
  assert(s.todayTasks[0].text === "买菜", "顺序保持");

  s = reducer(s, { type: "ADD_TASK", section: "future", text: "体检", dueDate: "2026-08-30" });
  s = reducer(s, { type: "ADD_TASK", section: "future", text: "缴费", dueDate: "2026-08-27" });
  // 未来日程按截止日期升序
  assert(s.futureTasks[0].text === "缴费", "未来日程按截止日期升序插入");
  assert(s.futureTasks[1].text === "体检", "较晚的排后面");
}

console.log("2) 完成与次日滚动");
{
  let s = fresh();
  s = reducer(s, { type: "ADD_TASK", section: "today", text: "任务A" });
  s = reducer(s, { type: "ADD_TASK", section: "today", text: "任务B" });
  s = reducer(s, { type: "TOGGLE_TODAY", id: s.todayTasks[0].id }); // 完成 A
  assert(s.todayTasks[0].completed === true, "打钩后 completed=true");

  s = reducer(s, { type: "END_DAY" }); // 切换到次日
  assert(s.currentDate === "2026-08-25", "日期前进一天");
  assert(s.todayTasks.length === 1 && s.todayTasks[0].text === "任务B", "未完成的顺延到次日");
  assert(s.history.length === 1 && s.history[0].date === "2026-08-24", "已完成的归档到历史(24日)");
  assert(s.history[0].tasks[0].text === "任务A", "归档内容正确");
  assert(s.history[0].tasks[0].plannedDate === "2026-08-24", "记录计划日期");
}

console.log("3) 未来日程到期自动移入当日末尾");
{
  let s = fresh();
  s = reducer(s, { type: "ADD_TASK", section: "today", text: "今日甲" });
  s = reducer(s, { type: "ADD_TASK", section: "future", text: "到期乙", dueDate: "2026-08-25" });
  s = reducer(s, { type: "END_DAY" });
  assert(s.todayTasks.length === 2, "次日有 2 条");
  assert(s.todayTasks[1].text === "到期乙", "到期任务追加到当日末尾");
  assert(s.futureTasks.length === 0, "未来列表已清空");
}

console.log("4) 拖动排序与跨区移动");
{
  let s = fresh();
  s = reducer(s, { type: "ADD_TASK", section: "today", text: "A" });
  s = reducer(s, { type: "ADD_TASK", section: "today", text: "B" });
  s = reducer(s, { type: "ADD_TASK", section: "today", text: "C" });
  s = reducer(s, { type: "REORDER", section: "today", from: 0, to: 2 });
  assert(s.todayTasks.map((t) => t.text).join() === "B,C,A", "当日内部排序");
  // B -> 未来（带截止日期）
  s = reducer(s, { type: "MOVE_TASK", id: s.todayTasks[0].id, to: "future", toIndex: 0, dueDate: "2026-09-01" });
  assert(s.todayTasks.length === 2 && s.futureTasks.length === 1, "当日->未来移动");
  assert(s.futureTasks[0].dueDate === "2026-09-01", "截止日期已设置");
  // 未来 -> 当日（保留隐藏截止时间）
  const futId = s.futureTasks[0].id;
  s = reducer(s, { type: "MOVE_TASK", id: futId, to: "today", toIndex: 0 });
  assert(s.todayTasks.length === 3 && s.futureTasks.length === 0, "未来->当日移动");
  assert(s.todayTasks[0].dueDate === "2026-09-01", "隐藏截止时间保留");
  // 再拖回未来 -> 自动沿用原截止日期
  s = reducer(s, { type: "MOVE_TASK", id: futId, to: "future", toIndex: 0 });
  assert(s.futureTasks[0].dueDate === "2026-09-01", "拖回未来沿用原截止日期");
}

console.log("5) 编辑规则");
{
  let s = fresh();
  s = reducer(s, { type: "ADD_TASK", section: "future", text: "原", dueDate: "2026-08-30" });
  const id = s.futureTasks[0].id;
  s = reducer(s, { type: "MOVE_TASK", id, to: "today", toIndex: 0 }); // 带隐藏时间进当日
  s = reducer(s, { type: "EDIT_TASK", id, text: "改名", dueDate: "2026-09-09" }); // 编辑当日任务传了 dueDate
  assert(s.todayTasks[0].text === "改名", "当日任务可改名");
  assert(s.todayTasks[0].dueDate === "2026-08-30", "当日编辑不改隐藏截止时间");
}

console.log("6) 历史恢复");
{
  let s = fresh();
  s = reducer(s, { type: "ADD_TASK", section: "today", text: "旧任务" });
  s = reducer(s, { type: "TOGGLE_TODAY", id: s.todayTasks[0].id });
  s = reducer(s, { type: "END_DAY" });
  const histDate = "2026-08-24";
  const hid = s.history[0].tasks[0].id;
  assert(s.history.length === 1, "历史有一条");
  // 原计划日期已过 -> 恢复到未来（选择 8-28）
  s = reducer(s, { type: "RESTORE", entryDate: histDate, id: hid, target: "future", dueDate: "2026-08-28" });
  assert(s.history.length === 0, "恢复后历史清空该条");
  assert(s.futureTasks.length === 1 && s.futureTasks[0].dueDate === "2026-08-28", "恢复到未来日程");
  assert(s.futureTasks[0].completed === false, "恢复后未完成");
}

console.log("7) 未来日程打钩 -> 立即归档");
{
  let s = fresh();
  s = reducer(s, { type: "ADD_TASK", section: "future", text: "提前完成", dueDate: "2026-09-05" });
  const id = s.futureTasks[0].id;
  s = reducer(s, { type: "COMPLETE_FUTURE", id });
  assert(s.futureTasks.length === 0, "未来列表移除");
  assert(s.history[0].tasks[0].text === "提前完成", "进入历史");
  assert(s.history[0].tasks[0].plannedDate === "2026-09-05", "计划日期为原截止日期");
}

console.log("8) 多日未打开 -> 日期追赶");
{
  let s = fresh();
  s = reducer(s, { type: "ADD_TASK", section: "today", text: "T1" });
  s = reducer(s, { type: "TOGGLE_TODAY", id: s.todayTasks[0].id });
  s = reducer(s, { type: "ADD_TASK", section: "future", text: "F1", dueDate: "2026-08-26" });
  s = reducer(s, { type: "ROLLOVER_TO", key: "2026-08-27" }); // 从 8-24 直接跳到 8-27
  assert(s.currentDate === "2026-08-27", "日期跳到目标日");
  assert(s.history[0].date === "2026-08-24", "8-24 已完成归档");
  assert(s.todayTasks.some((t) => t.text === "F1"), "期间到期的 F1 被拉入当日");
}

console.log("9) 删除（永久）");
{
  let s = fresh();
  s = reducer(s, { type: "ADD_TASK", section: "today", text: "X" });
  const id = s.todayTasks[0].id;
  s = reducer(s, { type: "DELETE_TASK", id });
  assert(s.todayTasks.length === 0, "当日任务删除");
  assert(s.history.length === 0, "不进入历史");
}

console.log("10) 清空历史");
{
  let s = fresh();
  s = reducer(s, { type: "ADD_TASK", section: "today", text: "A" });
  s = reducer(s, { type: "TOGGLE_TODAY", id: s.todayTasks[0].id });
  s = reducer(s, { type: "END_DAY" });
  s = reducer(s, { type: "CLEAR_HISTORY" });
  assert(s.history.length === 0, "历史已清空");
}

console.log("11) 日期回退（ROLLBACK_TO）");
{
  let s = fresh();
  s = reducer(s, { type: "ADD_TASK", section: "today", text: "旧任务" }); // 无截止日期
  s = reducer(s, { type: "ADD_TASK", section: "future", text: "到期任务", dueDate: "2026-08-28" });
  // 快进到 8-28：到期任务被拉入当日
  s = reducer(s, { type: "ROLLOVER_TO", key: "2026-08-28" });
  assert(s.todayTasks.length === 2, "快进后当日 2 条");
  // 回退到 8-24
  s = reducer(s, { type: "ROLLBACK_TO", key: "2026-08-24" });
  assert(s.currentDate === "2026-08-24", "日期回退到目标日");
  assert(s.todayTasks.length === 1 && s.todayTasks[0].text === "旧任务", "无截止日期的留在当日");
  assert(
    s.futureTasks.length === 1 && s.futureTasks[0].text === "到期任务",
    "隐藏截止日期更晚的任务放回未来"
  );
}

console.log("12) 回退到不早于当前日期时无操作");
{
  let s = fresh();
  s = reducer(s, { type: "ROLLBACK_TO", key: "2026-08-25" });
  assert(s.currentDate === "2026-08-24", "回退到更晚的日期被忽略");
  assert(s.todayTasks.length === 0 && s.futureTasks.length === 0, "数据不变");
}

console.log("13) 未来日程起始-截止区间");
{
  let s = fresh(); // currentDate = 2026-08-24
  // 不填起始 -> 默认创建日的下一天
  s = reducer(s, { type: "ADD_TASK", section: "future", text: "仅截止", dueDate: "2026-08-30" });
  assert(s.futureTasks[0].startDate === "2026-08-25", "起始日期默认次日");
  // 自定义区间
  s = reducer(s, { type: "ADD_TASK", section: "future", text: "自定义", startDate: "2026-08-28", dueDate: "2026-09-02" });
  const t2 = s.futureTasks.find((t) => t.text === "自定义");
  assert(t2.startDate === "2026-08-28" && t2.dueDate === "2026-09-02", "自定义起始-截止区间");
  // 起始晚于截止 -> 自动修正为截止日
  s = reducer(s, { type: "ADD_TASK", section: "future", text: "倒挂", startDate: "2026-09-10", dueDate: "2026-09-02" });
  const t3 = s.futureTasks.find((t) => t.text === "倒挂");
  assert(t3.startDate === "2026-09-02", "起始晚于截止时自动修正");
}

console.log("14) 完成百分比");
{
  let s = fresh();
  s = reducer(s, { type: "ADD_TASK", section: "today", text: "任务" });
  const id = s.todayTasks[0].id;
  // 设 60%
  s = reducer(s, { type: "EDIT_TASK", id, text: "任务", progress: 60 });
  assert(s.todayTasks[0].progress === 60 && !s.todayTasks[0].completed, "设 60% -> 进行中且进度 60");
  // 设 100% -> 视为完成
  s = reducer(s, { type: "EDIT_TASK", id, text: "任务", progress: 100 });
  assert(s.todayTasks[0].completed === true && s.todayTasks[0].progress === 100, "设 100% -> 自动视为完成");
  // 从完成改回 40% -> 取消完成
  s = reducer(s, { type: "EDIT_TASK", id, text: "任务", progress: 40 });
  assert(s.todayTasks[0].completed === false && s.todayTasks[0].progress === 40, "从完成改回 40% -> 取消完成");
  // 清除进度（完成状态不变）
  s = reducer(s, { type: "EDIT_TASK", id, text: "任务", progress: null });
  assert(s.todayTasks[0].progress === null && !s.todayTasks[0].completed, "清除进度且保持未完成");
  // 打钩后进度保留
  s = reducer(s, { type: "TOGGLE_TODAY", id });
  assert(s.todayTasks[0].completed === true, "打钩完成");
}

console.log("15) 分组：把某组中间任务移到新组后原组自动收敛为一段");
{
  let s = fresh();
  s = reducer(s, { type: "SET_SETTINGS", patch: { showGroups: true } });
  // 组 x: a,d ; 组 y: 1,2,3 ; 组 z: A,B,C
  const add = (text, group) => reducer(s, { type: "ADD_TASK", section: "today", text, group });
  for (const [t, g] of [["a", "x"], ["d", "x"], ["1", "y"], ["2", "y"], ["3", "y"], ["A", "z"], ["B", "z"], ["C", "z"]]) s = add(t, g);
  assert(s.todayTasks.map((x) => x.text).join("") === "ad123ABC", "初始顺序 ad 123 ABC");
  const bId = s.todayTasks.find((x) => x.text === "B").id;
  s = reducer(s, { type: "EDIT_TASK", id: bId, text: "B", group: "new" });
  // 期望：ad 123 B AC（无同名双段）
  assert(s.todayTasks.map((x) => x.text).join("") === "ad123BAC", "收敛后 ad 123 B AC");
  const segs = new Set();
  let ok = true;
  let prev = "\u0000";
  for (const t of s.todayTasks) {
    const k = t.group ?? "";
    if (k === prev) continue;
    if (segs.has(k)) ok = false;
    segs.add(k);
    prev = k;
  }
  assert(ok === true, "每个分组只出现一段");
}

console.log("16) 分组：删除分组后日程移入未分组（原组不再出现）");
{
  let s = fresh();
  s = reducer(s, { type: "SET_SETTINGS", patch: { showGroups: true } });
  const add = (text, group) => reducer(s, { type: "ADD_TASK", section: "today", text, group });
  for (const [t, g] of [["a", null], ["1", "y"], ["2", "y"], ["A", "z"], ["B", "z"]]) s = add(t, g);
  s = reducer(s, { type: "DELETE_GROUP", section: "today", group: "z" });
  const texts = s.todayTasks.map((x) => x.text);
  assert(!s.todayTasks.some((x) => x.group === "z"), "z 组已删除");
  assert(texts.filter((t) => t === "A" || t === "B").length === 2, "A、B 未消失");
  assert(texts.indexOf("A") > texts.indexOf("a"), "A/B 排在原未分组之后（未分组末尾）");
  assert(s.todayTasks.filter((x) => x.group === null).length === 3, "A/B 已归入未分组");
}

console.log("17) 关闭分组：自由排序、跨区移动与重新加载均保留混排顺序");
{
  let s = fresh();
  for (const section of ["today", "future"]) {
    for (const [name, group] of [["学1", "学习"], ["学2", "学习"], ["学3", "学习"], ["学4", "学习"], ["游1", "游戏"], ["游2", "游戏"], ["散1", null]]) {
      s = reducer(s, { type: "ADD_TASK", section, text: section === "today" ? name : `未来${name}`, group,
        dueDate: section === "future" ? "2026-08-30" : undefined });
    }
  }
  const groupById = new Map([...s.todayTasks, ...s.futureTasks].map((t) => [t.id, t.group]));
  const order = (tasks) => tasks.map((t) => t.text).join();
  const todayExpected = "学1,学2,游1,学3,学4,游2,散1";
  const futureExpected = "未来学1,未来散1,未来学2,未来学3,未来学4,未来游1,未来游2";
  s = reducer(s, { type: "REORDER", section: "today", from: 4, to: 2 });
  assert(order(s.todayTasks) === todayExpected, "关闭分组时，游戏日程可插入四个学习日程之间");
  s = reducer(s, { type: "REORDER", section: "future", from: 6, to: 1 });
  assert(order(s.futureTasks) === futureExpected, "关闭分组时，未来未分组日程也可插入学习日程之间");
  assert([...s.todayTasks, ...s.futureTasks].every((t) => t.group === groupById.get(t.id)), "自由混排不改变任何日程的隐藏分组");

  s = reducer(s, { type: "SET_SETTINGS", patch: { colorPreset: "forest" } });
  assert(order(s.todayTasks) === todayExpected && order(s.futureTasks) === futureExpected, "调整其它设置不重新聚拢隐藏分组");
  s = reducer(s, { type: "EDIT_TASK", id: s.todayTasks.find((t) => t.text === "游1").id, text: "游1", progress: 50 });
  assert(order(s.todayTasks) === todayExpected, "编辑完成进度不打乱手动混排顺序");
  s = reducer(s, { type: "TOGGLE_TODAY", id: s.todayTasks.find((t) => t.text === "游1").id });
  assert(order(s.todayTasks) === todayExpected, "勾选完成不打乱手动混排顺序");
  s = reducer(fresh(), { type: "LOAD", data: JSON.parse(JSON.stringify(s)) });
  assert(order(s.todayTasks) === todayExpected && order(s.futureTasks) === futureExpected, "保存后重新加载仍保留当日与未来的混排顺序");

  const movedId = s.futureTasks.find((t) => t.text === "未来游2").id;
  s = reducer(s, { type: "MOVE_TASK", id: movedId, to: "today", toIndex: 1 });
  assert(order(s.todayTasks) === "学1,未来游2,学2,游1,学3,学4,游2,散1" && !s.futureTasks.some((t) => t.id === movedId), "跨区移动也能插入隐藏分组中间且只移动目标日程");
  assert(s.todayTasks.find((t) => t.id === movedId).group === "游戏", "关闭分组时跨区移动保留原分组");

  const mixed = s;
  s = reducer(s, { type: "SET_SETTINGS", patch: { showGroups: true } });
  const singleSegments = (tasks) => {
    const segments = tasks.filter((t, i) => i === 0 || t.group !== tasks[i - 1].group).map((t) => t.group);
    return new Set(segments).size === segments.length;
  };
  assert(singleSegments(s.todayTasks) && singleSegments(s.futureTasks), "重新开启分组时，两列表的同名分组恢复为连续一段");
  assert([...s.todayTasks, ...s.futureTasks].every((t) => t.group === groupById.get(t.id)), "重新开启分组不会修改原分组归属");
  assert(["todayTasks", "futureTasks"].every((key) => ["学习", "游戏", null].every((group) =>
    s[key].filter((t) => t.group === group).map((t) => t.id).join() === mixed[key].filter((t) => t.group === group).map((t) => t.id).join()
  )), "重新开启分组保持每个组内的相对顺序");
  const grouped = s;
  s = reducer(s, { type: "SET_SETTINGS", patch: { showGroups: false } });
  assert(order(s.todayTasks) === order(grouped.todayTasks) && order(s.futureTasks) === order(grouped.futureTasks), "再次关闭分组不会额外改变当前顺序");
}

console.log("18) 分组目录：旧数据迁移与空组持久化");
{
  assert(freshData().groups.length === 0, "全新数据从空分组目录开始");
  const legacy = {
    ...fresh(),
    todayTasks: [{ id: "a", text: "甲", group: " 学习 " }, { id: "b", text: "乙", group: "工作" }],
    futureTasks: [{ id: "c", text: "丙", group: "学习" }, { id: "d", text: "丁", group: "游戏" }],
    history: [{ date: "2026-08-23", tasks: [{ id: "h", group: "旧分组" }] }],
  };
  delete legacy.groups;
  const migrated = normalizeData(legacy);
  assert(migrated.groups.join() === "学习,工作,游戏", "旧数据从当日和未来任务补齐去重分组，不从历史复活标签");
  const cleaned = normalizeData({ ...legacy, groups: [" 空组 ", "学习", "空组", "", "  ", 42, null] });
  assert(cleaned.groups.join() === "空组,学习,工作,游戏", "读取目录时保留空组、去重修剪名称并忽略无效项目");

  let s = fresh();
  for (const [text, group] of [["学1", "学习"], ["学2", "学习"], ["游1", "游戏"]]) {
    s = reducer(s, { type: "ADD_TASK", section: "today", text, group });
  }
  s = reducer(s, { type: "EDIT_TASK", id: s.todayTasks[0].id, text: "学1", group: "游戏" });
  s = reducer(s, { type: "MOVE_TASK", id: s.todayTasks[1].id, to: "today", toIndex: 2, group: "游戏" });
  assert(s.todayTasks.every((t) => t.group === "游戏") && s.groups.join() === "学习,游戏", "编辑和拖动将全组移走后，原组仍保留在目录中");
  assert(s.todayTasks.map((t) => t.text).join() === "学1,游1,学2", "目录更新不影响关闭分组时的指定插入顺序");
  s = reducer(fresh(), { type: "LOAD", data: normalizeData(JSON.parse(JSON.stringify(s))) });
  assert(s.groups.join() === "学习,游戏" && s.todayTasks.map((t) => t.text).join() === "学1,游1,学2", "保存重开后空组和自由排序均保留");
  s = reducer(s, { type: "ADD_TASK", section: "future", text: "新学习", group: "学习", dueDate: "2026-09-01" });
  assert(s.groups.join() === "学习,游戏" && s.futureTasks[0].group === "学习", "新增日程可复用空组且目录不重复");
  s = reducer(s, { type: "DELETE_TASK", id: s.futureTasks[0].id });
  assert(s.groups.includes("学习") && s.futureTasks.length === 0, "删除组内最后一条日程仍保留标签");
  s = reducer(s, { type: "DELETE_GROUP", section: "today", group: "学习" });
  assert(s.groups.join() === "游戏" && s.todayTasks.length === 3, "显式删除空分组会移除标签，不改变其他日程");
}

console.log("19) 分组目录：跨区删除与历史隔离");
{
  let s = fresh();
  s = reducer(s, { type: "ADD_TASK", section: "today", text: "今日工作", group: "工作" });
  s = reducer(s, { type: "ADD_TASK", section: "future", text: "未来工作", group: "工作", dueDate: "2026-09-01" });
  s = reducer(s, { type: "ADD_TASK", section: "today", text: "学习", group: "学习" });
  s = reducer(s, { type: "DELETE_GROUP", section: "today", group: "工作" });
  assert(s.groups.join() === "工作,学习" && s.todayTasks.find((t) => t.text === "今日工作").group === null
    && s.futureTasks[0].group === "工作", "只删除当日分组时，未来同名分组仍保留且目录顺序不变");
  s = reducer(s, { type: "DELETE_GROUP", section: "future", group: "工作" });
  assert(s.groups.join() === "学习" && s.futureTasks[0].group === null, "标签删除连续处理两分区后移除目录，并将两边日程归入未分组");
  const before = s;
  s = reducer(s, { type: "DELETE_GROUP", section: "today", group: null });
  assert(s === before, "未分组不可删除，日程顺序和目录保持不变");

  s = reducer(s, { type: "TOGGLE_TODAY", id: s.todayTasks.find((t) => t.group === "学习").id });
  s = reducer(s, { type: "END_DAY" });
  s = reducer(s, { type: "ADD_TASK", section: "future", text: "读书", group: "读书", dueDate: "2026-09-01" });
  s = reducer(s, { type: "COMPLETE_FUTURE", id: s.futureTasks.find((t) => t.group === "读书").id });
  assert(s.groups.join() === "学习,读书" && ![...s.todayTasks, ...s.futureTasks].some((t) => t.group), "次日归档与未来提前完成都保留空组目录");
  s = reducer(s, { type: "DELETE_GROUP", section: "today", group: "学习" });
  s = reducer(s, { type: "DELETE_GROUP", section: "future", group: "读书" });
  s = reducer(s, { type: "SET_SETTINGS", patch: { showGroups: true } });
  s = normalizeData(JSON.parse(JSON.stringify(s)));
  assert(s.groups.length === 0 && s.history.flatMap((h) => h.tasks).some((t) => t.group === "学习"), "删除空组后修改设置和重开均不从历史复活标签，历史分组仍保留");
  const entry = s.history.find((h) => h.tasks.some((t) => t.group === "学习"));
  s = reducer(s, { type: "RESTORE", entryDate: entry.date, id: entry.tasks.find((t) => t.group === "学习").id, target: "today" });
  assert(s.groups.join() === "学习" && s.todayTasks.some((t) => t.group === "学习"), "主动恢复历史日程时重新加入它实际使用的分组");
  s = reducer(s, { type: "CLEAR_HISTORY" });
  assert(s.groups.join() === "学习", "清空历史不会恢复或删除其他分组标签");
}


console.log('20) 手机状态更新不可变与设置默认值');
{
  const data = freshData();
  assert(data.settings.autoNumber && data.settings.themeMode === 'system' && data.settings.colorPreset === 'seasalt', '编号开启、跟随系统、海盐默认值');
  assert(data.settings.todayPaneRatio === 0.45 && !data.settings.showGroups && !data.settings.progressDefaultZero, '分区比例及显示开关默认值');
  const before = JSON.stringify(data);
  const next = reducer(data, { type: 'ADD_TASK', section: 'today', text: '新增' });
  assert(JSON.stringify(data) === before && next !== data && next.settings !== data.settings, '变更不修改旧状态及嵌套设置');
  const changed = reducer(next, { type: 'EDIT_TASK', id: next.todayTasks[0].id, text: '新名称', progress: 35 });
  assert(next.todayTasks[0].text === '新增' && next.todayTasks[0].progress === null && changed.todayTasks[0].progress === 35, '编辑不修改原任务对象');
}

console.log('21) 自动定位仅由完成第一个未完成项触发');
{
  let s = fresh();
  s = reducer(s, { type: 'SET_SETTINGS', patch: { autoScrollNextOnComplete: true } });
  for (const text of ['甲', '乙', '丙']) s = reducer(s, { type: 'ADD_TASK', section: 'today', text });
  const ids = s.todayTasks.map(task => task.id);
  s = reducer(s, { type: 'TOGGLE_TODAY', id: ids[1] });
  assert(s.todayAnchorId === null, '完成非首个未完成任务不定位');
  s = reducer(s, { type: 'TOGGLE_TODAY', id: ids[0] });
  assert(s.todayAnchorId === ids[2], '完成首项跳过已完成项并定位下一未完成');
  s = reducer(s, { type: 'TOGGLE_TODAY', id: ids[0] });
  assert(s.todayAnchorId === ids[2], '取消完成不改变定位');
  s = reducer(s, { type: 'EDIT_TASK', id: ids[0], text: '甲修改', progress: 100 });
  assert(s.todayAnchorId === ids[2], '编辑百分比不额外触发定位');
  s = reducer(s, { type: 'SET_SETTINGS', patch: { autoScrollNextOnComplete: false } });
  assert(s.todayAnchorId === null, '关闭自动定位清空锚点');
}

console.log('22) 起始日期、未来进度及恢复与桌面边缘规则一致');
{
  let s = fresh();
  s = reducer(s, { type: 'ADD_TASK', section: 'future', text: '区间任务', startDate: '2026-08-25', dueDate: '2026-08-30' });
  const id = s.futureTasks[0].id;
  s = reducer(s, { type: 'ROLLOVER_TO', key: '2026-08-25' });
  assert(s.futureTasks.length === 1 && s.todayTasks.length === 0, '仅到起始日不会提前移入当日');
  s = reducer(s, { type: 'EDIT_TASK', id, text: '区间任务', progress: 100 });
  assert(s.futureTasks[0].completed && s.history.length === 0, '未来编辑至100%保持未来列表，与桌面一致');
  s = reducer(s, { type: 'COMPLETE_FUTURE', id });
  assert(s.history[0].date === '2026-08-25' && s.history[0].tasks[0].plannedDate === '2026-08-30', '未来勾选按当前日期归档并保留计划日期');
  s = reducer(s, { type: 'RESTORE', entryDate: '2026-08-25', id, target: 'future' });
  assert(!s.futureTasks[0].completed && s.futureTasks[0].dueDate === '2026-08-30' && s.futureTasks[0].progress === 100, '恢复沿用计划日期并保留原始进度');
  s = reducer(s, { type: 'MOVE_TASK', id, to: 'today', toIndex: 0 });
  s = reducer(s, { type: 'EDIT_TASK', id, text: '当日任务', startDate: '2026-09-01', dueDate: '2026-09-03' });
  assert(s.todayTasks[0].startDate === '2026-08-25' && s.todayTasks[0].dueDate === '2026-08-30', '编辑当日完整保留隐藏起止日期');
}

console.log('23) 整组移动、日期工具与归一化容错');
{
  let s = fresh();
  s = reducer(s, { type: 'SET_SETTINGS', patch: { showGroups: true } });
  for (const [text, group] of [['甲', '工作'], ['乙', '工作'], ['丙', '生活'], ['丁', null]]) s = reducer(s, { type: 'ADD_TASK', section: 'today', text, group });
  s = reducer(s, { type: 'MOVE_GROUP', section: 'today', group: '工作', toIndex: 4 });
  assert(s.todayTasks.map(task => task.text).join('') === '丙丁甲乙', '整组移动到队尾且组内顺序保留');
  assert(engine.addDays('2028-02-28', 1) === '2028-02-29' && engine.addDays('2026-12-31', 1) === '2027-01-01', '本地日历跨闰日及跨年');
  assert(engine.formatRange('2026-08-25', '2026-09-01') === '8月25日-9月1日' && engine.formatRange(null, '2026-08-25') === '8月25日', '时间区间文案与桌面一致');
  const raw = JSON.parse(JSON.stringify(s));
  raw.todayTasks[0].progress = 108.8;
  raw.settings.todayPaneRatio = NaN;
  raw.settings.colorPreset = '非法主题';
  const normalized = normalizeData(raw);
  assert(normalized.todayTasks[0].progress === 100 && normalized.settings.todayPaneRatio === 0.45 && normalized.settings.colorPreset === 'seasalt', '异常进度和设置回退安全默认值');
  assert(normalized instanceof model.AppData && normalized.todayTasks[0] instanceof model.Task && normalized.settings instanceof model.Settings, '存储读取恢复强类型对象及clone方法');
}

console.log(`\n结果: ${passed} 通过, ${failed} 失败`);
if (failed > 0) process.exit(1);
