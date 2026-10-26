// 使用实际材质工厂与修饰器验证自动分档，不渲染 UI、不改设备和日程数据。
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const require = createRequire(import.meta.url);
let ts;
for (const candidate of [process.env.TYPESCRIPT_PATH, 'typescript',
  'D:/Software/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript',
  path.join(root, '../Planer/node_modules/typescript')].filter(Boolean)) {
  try { ts = require(candidate); break; } catch {}
}
if (!ts) throw new Error('请设置 TYPESCRIPT_PATH 指向现有 TypeScript。');
let api26 = true;
let capable = true;
let level = 0;
let state = 1;
let failInfo = false;
let failLevel = false;
let queries = 0;
let allocations = 0;
const empty = { empty: true };
const uiMaterial = {
  Material: { empty }, MaterialState: { DISABLE: 2 }, MaterialLevel: { EXQUISITE: 0, GENTLE: 1, SMOOTH: 2 },
  ImmersiveStyle: { ULTRA_THIN: 0, REGULAR: 2, THICK: 3 },
  isImmersiveMaterialSupported: () => { queries++; return capable; },
  getMaterialInfo: () => { queries++; if (failInfo) throw new Error('读取失败'); return { state }; },
  getGlobalMaterialLevel: () => { queries++; if (failLevel) throw new Error('读取失败'); return level; },
  ImmersiveMaterial: class { constructor(options) { this.options = options; allocations++; } }
};
const modules = new Map();
function load(name) {
  if (modules.has(name)) return modules.get(name);
  const filename = path.join(root, 'entry/src/main/ets/theme', name + '.ets');
  const compiled = ts.transpileModule(readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, fileName: filename
  }).outputText;
  const module = { exports: {} };
  const sandbox = { module, exports: module.exports,
    require: request => request === '@kit.ArkUI' ? { uiMaterial, curves: {} } :
      request === '@kit.BasicServicesKit' ? { deviceInfo: { apiAvailable: () => api26 } } : load(path.basename(request)),
    Color: { Transparent: 'transparent' }, BlurStyle: { NONE: 'none' },
    ThemeColorMode: { DARK: 'dark', LIGHT: 'light' }, BorderStyle: { Solid: 'solid', Dashed: 'dashed' }
  };
  vm.runInNewContext(compiled, sandbox, { filename });
  modules.set(name, module.exports);
  return module.exports;
}
const { Materials, EditorSectionModifier, PlanerControlModifier, PlanerTabsModifier } = load('Appearance');
const { Palette } = load('Theme');
const palette = new Palette();
function node() {
  const values = {};
  const calls = [];
  const proxy = new Proxy({}, { get: (_, key) => (...args) => {
    values[key] = args[0]; calls.push(String(key)); return proxy;
  } });
  return { values, calls, proxy };
}
function control(selected = false, danger = false, active = true, outline) {
  const result = node();
  new PlanerControlModifier(palette, selected, danger, active, outline).applyNormalAttribute(result.proxy);
  return result;
}
let passed = 0;
function assert(value, label) { if (!value) throw new Error(label); passed++; console.log('✓ ' + label); }

assert(Materials.supported(), '高档设备继续使用系统沉浸材质');
assert(Materials.adaptiveTint('#00000000') === '#00000000', '高档保留通透赋色');
const high = control();
assert(high.values.systemMaterial.options.materialColor === '#00000000', '普通按钮高档继续采样背景');
assert(Materials.toolbar(palette).options.materialColor === '#122e7cf6', '高档底栏保留轻主题色');
assert(Materials.button(palette).options.materialColor === 'transparent', '历史返回按钮高档保留通透材质');
const highSheet = Materials.sheetMaterial(palette);
assert([0, 1, 2, 3, 4].includes(highSheet.options.style) && /^#[0-9a-f]{2}ffffff$/i.test(highSheet.options.materialColor) &&
  parseInt(highSheet.options.materialColor.slice(1, 3), 16) > 0 && parseInt(highSheet.options.materialColor.slice(1, 3), 16) < 255,
  '半模态允许独立调节有效厚度与半透明面板赋色');
assert(Materials.dialog(palette).options.style === 2 && Materials.dialog(palette).options.materialColor === '#40ffffff', '普通确认弹窗保留原有常规厚度');
const group = control(true, false, true, 'solid');
assert(group.values.border.width === 0 && group.values.border.radius === 12 && group.calls.indexOf('border') < group.calls.indexOf('systemMaterial'), '材质标签清除外加轮廓时保留圆角，避免高光形状被重置');
assert(group.values.systemMaterial.options.materialColor === '#2A2e7cf6', '选中标签用主题淡染表达状态');
const nativeSection = node();
new EditorSectionModifier(palette).applyNormalAttribute(nativeSection.proxy);
assert(nativeSection.values.systemMaterial.options.applyShadow === false &&
  highSheet.options.applyShadow === true && high.values.systemMaterial.options.applyShadow === true,
  '只关闭动态分区的材质阴影，半模态与按钮仍保留系统阴影');
assert(nativeSection.values.shadow?.radius === 0 && Materials.sectionShadow(palette).fill === false &&
  nativeSection.calls.indexOf('shadow') > nativeSection.calls.indexOf('systemMaterial'),
  '清除原生标题内部阴影，独立投影不填黑透明材质内部');


level = 2;
assert(Materials.supported(), '低档仍保留官方自动降档，不切换自绘材质');
assert(Materials.adaptiveTint('#00000000') === undefined, '低档取消透明赋色覆盖');
const lowSection = node();
new EditorSectionModifier(palette).applyNormalAttribute(lowSection.proxy);
assert(lowSection.values.systemMaterial.options.materialColor === undefined &&
  lowSection.values.systemMaterial.options.applyShadow === false && lowSection.values.shadow?.radius === 0,
  '低档保留系统默认有色背板，同时采用跟随尺寸的单层普通阴影');

assert([Materials.toolbar(palette), Materials.dialog(palette), Materials.button(palette), Materials.sheetMaterial(palette)]
  .every(item => item.options.materialColor === undefined), '底栏、确认框、返回按钮和半模态低档都由系统提供默认底色');
const low = control();
assert(low.values.systemMaterial.options.materialColor === undefined && low.values.systemMaterial !== high.values.systemMaterial,
  '低档默认材质与高档透明材质分别缓存');
assert(control(true).values.systemMaterial.options.materialColor === undefined &&
  control(false, true).values.systemMaterial.options.materialColor === undefined, '强调和危险按钮低档同样不覆盖系统默认背板');
level = 1;
const gentle = control();
assert(gentle.values.systemMaterial === high.values.systemMaterial, '中档恢复原有通透材质，不误用低档缓存');
assert(Materials.adaptiveTint('#182e7cf6') === '#182e7cf6', '中档样式及赋色继续交由系统处理');

// 模型只复现平台节点分档与主题回填规则，不模拟像素、GPU 或真实 ArkUI 布局。
// OpenHarmony 21b150e7bb1d5308846f8e5be8ef0482fb433315：
// ui_material.cpp 的 LowerGearLevel 仅把 SheetPage 的 GENTLE 降为 SMOOTH；
// sheet_presentation_pattern.cpp 的中低档主题更新把非空 systemMaterial（含 empty）回填为主题色。
function materialEffect(material, carrier, deviceLevel) {
  if (material === undefined || material === empty) return { filter: false, background: undefined };
  const actualLevel = carrier === 'SheetPage' && deviceLevel === 1 ? 2 : deviceLevel;
  return { filter: actualLevel !== 2,
    background: actualLevel === 2 ? (material.options.materialColor ?? 'system-default') : undefined };
}
function sheetEffects(deviceLevel) {
  level = deviceLevel;
  const options = Materials.sheet(palette, { height: '90%' });
  const usesContent = Materials.sheetUsesContentSurface();
  const native = materialEffect(options.systemMaterial, 'SheetPage', deviceLevel);
  const content = materialEffect(usesContent ? Materials.sheetMaterial(palette) : undefined, 'ColumnInNavigationTitle', deviceLevel);
  const themeWouldOverwrite = options.systemMaterial !== undefined && deviceLevel !== 0;
  return { options, usesContent, native, content, themeWouldOverwrite };
}
const historicalGentle = materialEffect(Materials.toolbar(palette), 'SheetPage', 1);
assert(!historicalGentle.filter && historicalGentle.background === '#122e7cf6',
  '平台模型能复现旧缺陷：给中档 SheetPage 与底栏相同材质仍退为半透明色块');

const onDisappear = () => {};
const options = { height: '94%', dragBar: true, onDisappear, backgroundColor: 'stale-color', blurStyle: 'stale-blur' };
level = 0;
assert(Materials.sheet(palette, options) === options && options.height === '94%' && options.onDisappear === onDisappear,
  '加厚不影响半模态高度、手势与关闭回调');
assert(options.backgroundColor === undefined && options.blurStyle === undefined && options.systemMaterial.options.style === highSheet.options.style &&
  options.systemMaterial.options.materialColor === highSheet.options.materialColor, '原生半模态清除冲突的背景色和模糊参数，不额外叠层');
const gentleSheet = sheetEffects(1);
assert(gentleSheet.usesContent && gentleSheet.content.filter && !gentleSheet.native.filter,
  '中档只有标题通用背板参与材质滤镜，避开 SheetPage 的额外降档');
assert(gentleSheet.options.systemMaterial === undefined && !gentleSheet.themeWouldOverwrite &&
  gentleSheet.options.backgroundColor === 'transparent' && gentleSheet.options.blurStyle === 'none',
  '中档原生背板明确透明且不含材质对象，后续主题更新不会回填不透明底色');
// 重用选项时也清除先前的高档材质，避免只在首次打开时正确。
level = 1;
Materials.sheet(palette, options);
assert(options.systemMaterial === undefined && options.backgroundColor === 'transparent' && options.blurStyle === 'none' &&
  options.height === '94%' && options.onDisappear === onDisappear,
  '复用高档选项切至中档时清除旧材质，同时保留面板尺寸与关闭回调');
const smoothSheet = sheetEffects(2);
assert(smoothSheet.usesContent && !smoothSheet.content.filter && smoothSheet.content.background === 'system-default',
  '低档内容背板采用系统默认可读底色，遵循真实低档规则且不强制启用滤镜');
assert(smoothSheet.options.systemMaterial === undefined && !smoothSheet.themeWouldOverwrite &&
  smoothSheet.options.backgroundColor === 'transparent' && smoothSheet.options.blurStyle === 'none',
  '低档原生半模态不再叠加额外背景或默认材质');
const exquisiteSheet = sheetEffects(0);
assert(!exquisiteSheet.usesContent && exquisiteSheet.native.filter && !exquisiteSheet.content.filter,
  '高档保留单一原生半模态材质，不创建多余内容背板');
assert(exquisiteSheet.options.systemMaterial.options.style === highSheet.options.style &&
  exquisiteSheet.options.systemMaterial.options.materialColor === highSheet.options.materialColor,
  '高档半模态仍保留原厚度与赋色');
level = 0;
assert(Materials.sheetMaterial(palette).options.style === highSheet.options.style &&
  Materials.sheetMaterial(palette).options.materialColor === highSheet.options.materialColor,
  '恢复高档后沿用原有常规厚度和赋色，不残留中低档配置');
const tabs = node();
new PlanerTabsModifier(palette, 8).applyNormalAttribute(tabs.proxy);
assert(tabs.values.barFloatingStyle.barBottomMargin === 20 && tabs.values.barFloatingStyle.systemMaterial,
  '新底栏保留悬浮布局与安全区');

capable = false;
const unsupportedSheet = Materials.sheet(palette, options);
assert(unsupportedSheet.systemMaterial === empty && unsupportedSheet.backgroundColor === palette.panel &&
  unsupportedSheet.blurStyle === 'none', '不支持材质时清空复用面板旧材质并恢复可读底色');
assert(!Materials.supported() && !Materials.sheetUsesContentSurface() && Materials.sheetMaterial(palette) === undefined, '不支持材质的设备不创建内容背板或沉浸材质');
const fallbackSection = node();
new EditorSectionModifier(palette).applyNormalAttribute(fallbackSection.proxy);
assert(fallbackSection.values.systemMaterial === empty && fallbackSection.values.backgroundColor === '#B8ffffff' &&
  fallbackSection.values.shadow?.fill === false, '不支持材质时保留可读分区底色与同一套普通阴影');

const fallback = control(true, false, true, 'dashed');
assert(fallback.values.systemMaterial === empty && fallback.values.backgroundColor === '#80dce9ff', '真正不支持时继续采用现有可读轻色回退');
assert(fallback.values.border.width === 1 && fallback.values.border.radius === 12 && fallback.values.border.style === 'dashed',
  '回退轮廓只画在真实按钮上，保持相同尺寸与圆角');
capable = true; state = 2;
assert(!Materials.supported() && !Materials.sheetUsesContentSurface() && control().values.systemMaterial === empty, '应用材质配置关闭时采用普通按钮且不创建内容背板');
state = 1; failInfo = true;
assert(!Materials.supported() && !Materials.sheetUsesContentSurface(), '能力查询失败时不冒险使用透明半模态和内容材质');
failInfo = false; failLevel = true;
assert(Materials.adaptiveTint('#00000000') === undefined, '档位读取失败时交由系统默认赋色');
const unknownSheet = Materials.sheet(palette, { height: 400 });
assert(Materials.sheetUsesContentSurface() && unknownSheet.systemMaterial === undefined &&
  unknownSheet.backgroundColor === 'transparent' && unknownSheet.blurStyle === 'none' &&
  Materials.sheetMaterial(palette).options.style === 0 && Materials.sheetMaterial(palette).options.materialColor === undefined,
  '档位查询失败仍由内容背板使用系统默认赋色，不把材质交回会额外降档的原生半模态');
failLevel = false;

api26 = false;
const queryCount = queries;
const allocationCount = allocations;
const oldSheet = Materials.sheet(palette, { height: 500 });
control(); Materials.toolbar(palette); Materials.dialog(palette); Materials.button(palette);
assert(!Materials.supported() && !Materials.sheetUsesContentSurface() && queries === queryCount && allocations === allocationCount, '最低兼容版本不调用 API 26 材质接口，也不创建内容材质背板');
assert(oldSheet.backgroundColor === palette.panel && oldSheet.blurStyle === 'none' && oldSheet.height === 500,
  '旧系统半模态仍为可读背景并保留高度');
const oldTabs = node(); new PlanerTabsModifier(palette).applyNormalAttribute(oldTabs.proxy);
assert(oldTabs.values.barBackgroundColor === palette.panel && oldTabs.values.barHeight === 64, '旧系统继续使用普通底栏');
// 运行真实刷新管理器，验证不同表单的可视区域和生命周期隔离。
const sectionSource = readFileSync(path.join(root, 'entry/src/main/ets/components/MaterialSection.ets'), 'utf8');
const managerSource = sectionSource.slice(sectionSource.indexOf('class SectionRefreshFrame'), sectionSource.indexOf('// 正文决定高度'));
const refreshModule = { exports: {} };
vm.runInNewContext(ts.transpileModule(managerSource, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, { module: refreshModule, exports: refreshModule.exports, FrameCallback: class {} });
const refresh = refreshModule.exports.EditorMaterialRefresh;
const frames = [];
const invalidated = [];
const nodes = new Map();
function frameNode(id, top, height, visible = true) {
  return { isAttached: () => true, isVisible: () => visible,
    getPositionToWindowWithTransform: () => ({ x: 0, y: top }),
    getMeasuredSize: () => ({ width: 600, height: height * 2 }),
    invalidate: () => invalidated.push(id) };
}
const refreshContext = { postFrameCallback: callback => frames.push(callback),
  getFrameNodeById: id => nodes.get(id), px2vp: value => value / 2 };
nodes.set('checkin-editor-scroll', frameNode('scroll', 100, 300));
nodes.set('checkin-visible', frameNode('checkin-visible', 150, 80));
nodes.set('checkin-outside', frameNode('checkin-outside', 450, 80));
nodes.set('checkin-hidden', frameNode('checkin-hidden', 200, 80, false));
refresh.register(refreshContext, 'checkin-visible', 'checkin-editor-scroll');
refresh.register(refreshContext, 'checkin-outside', 'checkin-editor-scroll');
refresh.register(refreshContext, 'checkin-hidden', 'checkin-editor-scroll');
refresh.request(refreshContext);
assert(frames.length === 1, '多个分区和滚动请求合并为一次帧回调');
frames.shift().onFrame();
assert(invalidated.join(',') === 'checkin-visible', '没有日程编辑页时，打卡独立刷新可见分区并跳过屏外与隐藏节点');
nodes.set('task-editor-scroll', frameNode('task-scroll', 700, 200));
nodes.set('task-visible', frameNode('task-visible', 750, 70));
refresh.register(refreshContext, 'task-visible');
frames.shift().onFrame();
assert(invalidated.slice(-2).join(',') === 'checkin-visible,task-visible', '共用管理器按各自视口刷新，日程默认视口保持兼容');
invalidated.length = 0;
refresh.request(refreshContext);
refresh.unregister('checkin-visible');
refresh.unregister('checkin-outside');
refresh.unregister('checkin-hidden');
frames.shift().onFrame();
assert(invalidated.join(',') === 'task-visible', '关闭打卡表单后，已排队帧不再触碰其材质节点');
refresh.unregister('task-visible');
refresh.request(refreshContext);
assert(frames.length === 0, '全部分区退出后停止提交刷新帧');
console.log(`Materials regression: ${passed} assertions passed.`);
