// 执行真实滑块、手势回调和页面导航方法；动画环境只记录参数并立即提交状态。
// 不模拟 ArkUI 渲染、真实触摸、GPU 或读屏，不访问设备和用户数据。
import { createRequire } from 'node:module';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const require = createRequire(import.meta.url);
let ts;
for (const candidate of [process.env.TYPESCRIPT_PATH, 'typescript', path.join(root, '../Planer/node_modules/typescript'),
  'D:/Software/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'].filter(Boolean)) {
  try { ts = require(candidate); break; } catch {}
}
if (!ts) throw new Error('请设置 TYPESCRIPT_PATH 指向现有 TypeScript 模块。');
function compile(source, filename) {
  const result = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2021 }, fileName: filename, reportDiagnostics: true });
  const errors = (result.diagnostics || []).filter(value => value.category === ts.DiagnosticCategory.Error);
  if (errors.length) throw new Error(errors.map(value => value.messageText).join('\n'));
  return result.outputText;
}
const modules = new Map();
function model(name) {
  if (modules.has(name)) return modules.get(name);
  const filename = path.join(root, 'entry/src/main/ets/model', name + '.ets');
  const module = { exports: {} }; modules.set(name, module.exports);
  vm.runInThisContext('(function(require,module,exports){' + compile(readFileSync(filename, 'utf8'), filename) + '\n})',
    { filename })(request => model(path.basename(request)), module, module.exports);
  return module.exports;
}
const modelApi = { ...model('PlanerModel'), ...model('CheckInModel'), ...model('PlanerEngine'), ...model('CheckInEngine') };
const componentDir = path.join(root, 'entry/src/main/ets/components');
const source = name => readFileSync(path.join(componentDir, name + '.ets'), 'utf8');
const filterSource = source('CheckInFilter');
const viewSource = source('CheckInView');
const toggleSource = source('CheckInToggleButton');
const appearanceSource = readFileSync(path.join(root, 'entry/src/main/ets/theme/Appearance.ets'), 'utf8');
const feedbackSource = appearanceSource.slice(appearanceSource.indexOf('export class ButtonFeedback'),
  appearanceSource.indexOf('const controlMaterials:')).replace('export class', 'class');
const timers = { next: 0, callbacks: new Map(),
  set(callback) { const id = ++this.next; this.callbacks.set(id, callback); return id; },
  clear(id) { this.callbacks.delete(id); },
  flush() { const current = [...this.callbacks.values()]; this.callbacks.clear(); current.forEach(callback => callback()); }
};
let now = 1000;
const TouchType = { Down: 0, Up: 1, Move: 2, Cancel: 3 };
function effect(options) { return { ...options, combine(other) { return effect({...options,combined:other}); },
  animation(value) { this.animationOptions=value; return this; } }; }
function callback(text, signature) {
  const at = text.indexOf(signature);
  if (at < 0) throw new Error('缺少真实回调：' + signature);
  let depth = 1;
  const start = at + signature.length;
  for (let index = start; index < text.length; index++) {
    if (text[index] === '{') depth++;
    if (text[index] === '}' && --depth === 0) return text.slice(start, index);
  }
  throw new Error('未闭合的真实回调：' + signature);
}
function argumentsOf(text, signature) {
  const at=text.indexOf(signature);
  if(at<0)throw new Error('缺少实际组件参数：'+signature);
  const scanner=ts.createScanner(ts.ScriptTarget.Latest,true,ts.LanguageVariant.Standard,text.slice(at));
  let depth=0;let end=0;
  while(true) {
    const kind=scanner.scan();if(kind===ts.SyntaxKind.EndOfFileToken)break;
    if(kind===ts.SyntaxKind.OpenParenToken)depth++;
    if(kind===ts.SyntaxKind.CloseParenToken && --depth===0){end=scanner.getTextPos();break;}
  }
  const call=text.slice(at,at+end).replace(/^\./,'');
  const ast=ts.createSourceFile('actual-arguments.ts','const actual='+call+';',ts.ScriptTarget.Latest,true,ts.ScriptKind.TS);
  const expression=ast.statements[0]?.declarationList?.declarations[0]?.initializer;
  if(ast.parseDiagnostics.length || !expression || !ts.isCallExpression(expression))throw new Error('参数解析失败：'+signature);
  return expression.arguments.map(argument=>argument.getText(ast));
}
function makeClass(name, text, appended = '') {
  const start = text.indexOf('@Component');
  const end = text.indexOf('  @Builder', start);
  if (start < 0 || end < 0) throw new Error('缺少组件方法边界：' + name);
  const core = text.slice(start, end);
  const watches = [...core.matchAll(/@Watch\('([^']+)'\)\s+(?:private\s+)?(\w+)/g)]
    .map(match => ({ method: match[1], field: match[2] }));
  const classSource = core.replace('@Component', '').replace('export struct ' + name, 'class ' + name)
    .replace(/@StorageProp\('[^']+'\)\s*/g, '').replace(/@Watch\('[^']+'\)\s*/g, '').replace(/@(?:Prop|State)\s+/g, '') + `
    getUIContext() { return {
      animateTo: (options, change) => { (this.testAnimations ||= []).push(options); change(); if(options.onFinish)options.onFinish(); },
      getHostContext: () => null,
      getFrameNodeById: id => this.testNodes?.get(id) || null,
      px2vp: value => value / (this.testDensity || 1),
      postFrameCallback: callback => { (this.testFrames ||= []).push(callback); },
      getPromptAction: () => ({ showToast: options => { (this.testToasts ||= []).push(options.message); },
        showDialog: options => { this.testDialogOptions=options; return this.testDialogPromise || Promise.resolve({index:0}); } })
    }; }
    ${appended}
  }
  globalThis.ComponentClass=${name};`;
  const context = vm.createContext({ ...modelApi, console, TouchType, HitTestMode: {Default:'default',None:'none'},
    DismissReason: { PRESS_BACK: 0 },
    Date: class extends Date { static now() { return now; } },
    Palette: class {}, Scroller: class {
      scrollBy(x,y) { (this.calls ||= []).push([x,y]); }
      scrollToIndex(index,smooth,align) { (this.indexCalls ||= []).push({index,smooth,align}); }
    },
    ScrollAlign: {START:'start'}, NestedScrollMode: { PARENT_FIRST:'parent-first', SELF_FIRST:'self-first' },
    Motion: { spring: () => ({ motion: 'spring' }), quick: () => ({ motion: 'quick' }) },
    TransitionEffect: { IDENTITY: {identity:true}, OPACITY:effect({opacity:true}),
      translate: options => effect({ translate: options }), asymmetric: (enter, exit) => effect({ enter, exit }) },
    Materials: { confirmation: (_palette, options) => options },
    CheckInFocusFrame: class { constructor(callback) { this.callback=callback; } },
    curves: { springMotion: (...values) => values },
    setTimeout: callback => timers.set(callback), clearTimeout: id => timers.clear(id)
  });
  vm.runInContext(compile(feedbackSource + classSource, name + '.ets'), context);
  return { Class: context.ComponentClass, watches };
}
function watches(instance, bindings) {
  for (const binding of bindings) {
    let value = instance[binding.field];
    Object.defineProperty(instance, binding.field, { configurable: true, get: () => value,
      set(next) { if (Object.is(next, value)) return; value = next; instance[binding.method](); } });
  }
}
function filterClass(name, text) {
  const accessible = text.match(/\.accessibilityText\((this\.labels\[index\].+)\)\s*\n/)?.[1];
  if (!accessible) throw new Error('缺少实际筛选按钮无障碍文案');
  return makeClass(name, text, `
    accessibleFromView(index,mode) { return ${accessible}; }
    touchFromView(event) { ${callback(text, '.onTouch((event: TouchEvent) => {')} }
    panStartFromView(event) { ${callback(text, '.onActionStart((event: GestureEvent) => {')} }
    panUpdateFromView(event) { ${callback(text, '.onActionUpdate((event: GestureEvent) => {')} }
    panEndFromView() { ${callback(text, '.onActionEnd(() => {')} }
    panCancelFromView() { ${callback(text, '.onActionCancel(() => {')} }
  `);
}
const filter = filterClass('CheckInFilter', filterSource);
const theme = filterClass('ThemeModePicker', source('ThemeModePicker'));
const detailHeader = viewSource.slice(viewSource.indexOf('@Builder private detailHeader('), viewSource.indexOf('@Builder private modalHeader('));
const detailTitles = [...detailHeader.matchAll(/Text\((.+)\)\.fontSize\(/g)].map(value=>value[1]);
const modalBody = viewSource.slice(viewSource.indexOf('@Builder private modalBody('), viewSource.indexOf('@Builder private sheetContent('));
const detailAccess = modalBody.match(/\.accessibilityLevel\((.+)\)/)?.[1];
const detailHit = modalBody.match(/\.hitTestBehavior\((.+)\)/)?.[1];
const editorTransition = modalBody.match(/\.transition\((this\.selectedId[^\n]+)\)/)?.[1];
if (detailTitles.length!==2 || !detailAccess || !detailHit || !editorTransition) throw new Error('缺少真实详情标题、隐藏条件或新建编辑转场');
const overview=viewSource.slice(viewSource.indexOf('@Builder private overview('),viewSource.indexOf('@Builder private detailHeader('));
const listFrameChain=overview.match(/\}\s*(\.width\([^)]*\)(?:\s*\.\w+\([^)]*\))*\.id\('checkin-plan-lists'\))/)?.[1];
if(!listFrameChain)throw new Error('缺少列表实际外框属性链');
const timelineBuilder=viewSource.slice(viewSource.indexOf('@Builder private timelineList('),viewSource.indexOf('@Builder private manageButtonContent('));
const view = makeClass('CheckInView', viewSource, `
  detailTitleFromView() { return ${detailTitles[0]}; }
  detailSubtitleFromView() { return ${detailTitles[1]}; }
  detailAccessFromView() { return ${detailAccess}; }
  detailHitFromView() { return ${detailHit}; }
  editorTransitionFromView() { return ${editorTransition}; }
  listFrameFromView() {
    const frame={}; const attributes={width(value){frame.width=value;return attributes;},clip(value){frame.clip=value;return attributes;},
      id(value){frame.id=value;return attributes;}};
    attributes${listFrameChain};return frame;
  }
  listResizeFromView(_old,size) { ${callback(overview,'.onSizeChange((_old: SizeOptions, size: SizeOptions): void => {')} }
  timelineOptionsFromView() { return ${argumentsOf(timelineBuilder,'List({')[0]}; }
  timelineNestingFromView() { return ${argumentsOf(timelineBuilder,'.nestedScroll(')[0]}; }
`);
const toggle = makeClass('CheckInToggleButton', toggleSource, `
  touchFromView(event) { ${callback(toggleSource,'.onTouch((event: TouchEvent): void => {')} }
  clickFromView() { ${callback(toggleSource,'.onClick((): void => {')} }
  disappearFromView() { ${callback(toggleSource,'.onDisAppear((): void => {')} }
`);
function newFilter(type = filter, mode) {
  const instance = new type.Class(); watches(instance, type.watches);
  if (mode) instance.selectedMode = mode;
  instance.testSelections = [];
  instance.onSelect = value => { instance.testSelections.push(value); instance.selectedMode = value; };
  instance.aboutToAppear(); return instance;
}
function newView() {
  const instance = new view.Class(); watches(instance, view.watches);
  instance.data = new modelApi.AppData(); instance.data.currentDate = instance.data.lastRolloverDate = '2026-10-27';
  instance.data.checkIns = [Object.assign(new modelApi.CheckInItem(), {id:'a',name:'计划A',startDate:'2026-10-27'}),
    Object.assign(new modelApi.CheckInItem(), {id:'b',name:'计划B',startDate:'2026-10-27'})];
  instance.testActions = []; instance.testSheetChanges=[];
  instance.onAction = action => { instance.testActions.push(action); instance.data = modelApi.reduce(instance.data, action); };
  instance.onSheetChange = shown => instance.testSheetChanges.push(shown);
  instance.aboutToAppear(); return instance;
}
let passed = 0;
function assert(condition, message) { if (!condition) throw new Error(message); passed++; console.log('✓ ' + message); }
const close = (a,b) => Math.abs(a-b)<0.0001;

console.log('1) 两项滑块初始化、尺寸、夹紧与主题动画一致性');
{
  const f = newFilter(); f.resize({width:300});
  assert(f.selectedMode==='today' && f.selectedIndex()===0 && f.sliderX===0, '打卡筛选首次选中今天');
  assert(f.segmentWidth()===150 && f.pillWidth()===150 && f.pillHeight()===44, '两等宽槽位和44vp滑块使用实际几何方法');
  f.selectedMode='all';
  assert(f.sliderX===150, '外部选择全部后滑块定位第二项');
  assert(f.accessibleFromView(1,'all')==='全部计划，已选中' && f.accessibleFromView(0,'today')==='今天',
    '固定筛选按钮的真实无障碍文案只标记当前项');
  f.resize({width:480});
  assert(f.sliderX===240 && f.segmentWidth()===240, '非拖动尺寸变化重新对齐当前项');
  const before=f.trackWidth; f.resize({width:0}); f.resize({width:NaN}); f.resize({width:'50%'});
  assert(f.trackWidth===before, '无效宽度不会污染滑块坐标');
  f.selectedMode='unknown';
  assert(f.selectedIndex()===0 && f.sliderX===0, '未知外部筛选值回退今天');
  f.select(99); f.select(-3);
  assert(f.selectedMode==='today' && f.testSelections.slice(-2).join(',')==='all,today', '超范围索引被夹紧到两项边界');
  f.select(0.49); assert(f.sliderX===0, '不足半格回弹至第一项');
  f.select(0.51); assert(f.sliderX===240, '越过半格吸附第二项');
  const t=newFilter(theme,'light'); t.resize({width:720});
  f.snap(0); t.snap(0);
  assert(JSON.stringify(f.testAnimations.at(-1).curve)===JSON.stringify(t.testAnimations.at(-1).curve), '吸附使用与主题滑块相同的非线性弹簧参数');
  f.touchFromView({type:TouchType.Down});t.touchFromView({type:TouchType.Down}); now+=16;
  f.panStartFromView({offsetX:60});t.panStartFromView({offsetX:60});
  assert(close(f.pillWidth(),t.pillWidth()) && close(f.pillHeight(),t.pillHeight()) && close(f.pillX(),t.pillX()) && close(f.pillY(),t.pillY()),
    '相同槽宽和手势下伸缩及中心补偿与主题滑块一致');
  assert(JSON.stringify(f.testAnimations.at(-1).curve)===JSON.stringify(t.testAnimations.at(-1).curve), '跟手使用与主题滑块相同弹簧参数');
  f.aboutToDisappear();t.aboutToDisappear();
}
console.log('2) 实际拖动回调、取消、尺寸变化和迟到回调');
{
  const f=newFilter();f.resize({width:300});f.touchFromView({type:TouchType.Down});now+=16;
  f.panStartFromView({offsetX:75});
  assert(f.dragging && f.sliderX===75 && f.stretch>0 && f.stretch<=0.12, '真实手势开始进入局部跟手状态并限制伸长');
  timers.flush(); assert(f.stretch===0.02, '停留后实际放松回调将伸长收敛');
  f.resize({width:600});
  assert(f.sliderX===150, '拖动中尺寸变化保留所处槽位比例');
  f.panUpdateFromView({offsetX:75});
  assert(f.sliderX===150, '拖动中变宽后同一手指位置不跳回旧坐标');
  f.panUpdateFromView({offsetX:105});
  assert(f.sliderX===180, '变宽后新手指位移继续相对新基线跟手');
  f.panCancelFromView();
  assert(!f.dragging && f.sliderX===0 && f.stretch===0 && f.testSelections.length===0, '系统取消手势回到原选择且不提交筛选');
  const count=f.testAnimations.length;timers.flush();
  assert(f.testAnimations.length===count, '取消后没有迟到的放松动画');
  f.touchFromView({type:TouchType.Down});f.panStartFromView({offsetX:1000});f.panEndFromView();
  assert(f.selectedMode==='all' && f.sliderX===300, '越过右边界的拖动只提交全部计划');
  f.touchFromView({type:TouchType.Down});f.panStartFromView({offsetX:-1000});f.panEndFromView();
  assert(f.selectedMode==='today' && f.sliderX===0, '越过左边界的拖动只提交今天');
  f.touchFromView({type:TouchType.Down});f.panStartFromView({offsetX:50});f.aboutToDisappear();
  const animations=f.testAnimations.length;timers.flush();
  assert(f.testAnimations.length===animations, '组件离场清理放松定时器');
}
{
  const f=newFilter();f.resize({width:300});const selections=[];
  f.onSelect=value=>selections.push(value); // 模拟父 Prop 还没返回的连续输入。
  f.select(1);f.select(0);
  assert(selections.at(-1)==='today' && f.sliderX===0, '连续点击最终选择不被延迟的父级Prop吞掉');
  f.aboutToDisappear();
}
console.log('3) 实际页面导航、滚动控制器和过期焦点任务');
{
  const v=newView();const before=JSON.stringify(v.data);
  assert(!v.showAll, '页面首次展示今天列表');
  v.switchList(true);const forward=v.listTransition();
  assert(v.showAll && forward.enter.translate.x>=360 && forward.exit.translate.x===-forward.enter.translate.x, '切到全部时新列表从右进入，离场距离覆盖最小窗口');
  const animations=v.testAnimations.length;v.switchList(true);
  assert(v.testAnimations.length===animations, '重复选择当前列表不重复启动转场');
  v.switchList(false);const backward=v.listTransition();
  assert(!v.showAll && backward.enter.translate.x===-forward.enter.translate.x && backward.exit.translate.x===forward.enter.translate.x, '快速切回今天时转场方向反转且距离不缩短');
  v.windowWidth=320;v.listResizeFromView({}, {width:288});const narrow=v.listTransition();
  assert(Math.abs(narrow.enter.translate.x)>v.windowWidth && Math.abs(narrow.exit.translate.x)>v.listViewportWidth,
    '窄手机窗口的进退距离都越过可见区域');
  v.windowWidth=1200;v.listResizeFromView({}, {width:760});const wide=v.listTransition();
  assert(Math.abs(wide.enter.translate.x)>v.windowWidth && Math.abs(wide.exit.translate.x)>v.listViewportWidth,
    '大屏受限内容宽度时仍以整个窗口距离完成进退');
  v.listResizeFromView({}, {width:1400});const resizing=v.listTransition();
  assert(Math.abs(resizing.enter.translate.x)>1400 && Math.abs(resizing.exit.translate.x)>1400,
    '布局先于窗口属性更新时按最新实测宽度覆盖整个列表');
  const frame=v.listFrameFromView();
  assert(frame.width==='100%' && frame.clip===true && frame.id==='checkin-plan-lists', '列表外框实际属性裁切进退内容，避免卡片留在页边');
  v.openDetail(v.data.checkIns[0]);
  assert(v.sheetShown && v.selectedId==='a' && v.modal==='detail', '详情入口选择条目并打开同一弹层');
  const detailSubtitle=v.detailSubtitleFromView();
  assert(v.detailAccessFromView()==='auto' && v.detailHitFromView()==='default', '详情可见时恢复正常触摸与无障碍访问');
  v.editSelected();
  assert(v.modal==='editor' && v.editorItem.id==='a' && v.editorItem!==v.selected(), '二级编辑使用独立草稿且保留当前条目');
  assert(v.detailTitleFromView()==='计划A' && v.detailSubtitleFromView()===detailSubtitle,
    '常驻详情在二级页动画期间保持自己的标题和副标题');
  assert(v.detailAccessFromView()==='no-hide-descendants' && v.detailHitFromView()==='none',
    '被二级页覆盖的详情同时屏蔽命中和全部无障碍子节点');
  v.editorItem.name='未保存';v.backToDetail();
  assert(v.modal==='detail' && v.selected().name==='计划A' && v.sheetShown, '编辑返回详情不关闭弹层也不保存草稿');
  const controllers=[];
  for(const modal of ['detail','editor','backfill','range','history']){v.showModal(modal);controllers.push(v.activeScroller());}
  assert(new Set(controllers).size===5, '常驻详情与四个二级内容不共享滚动控制器');
  v.sheetActive=true;v.focusedInput='old-field';v.scheduleFocusedInputScroll();
  const version=v.focusScrollVersion;let measurements=0;v.ensureFocusedInputVisible=()=>{measurements++;};
  v.showModal('detail');for(const frame of v.testFrames||[])frame.callback();timers.flush();
  assert(v.focusedInput==='' && v.focusScrollVersion>version && measurements===0, '二级切换废弃旧焦点帧和定时测量');
  assert(JSON.stringify(v.data)===before, '列表切换、二级进入和返回不修改业务数据');
  v.pressedButton='old';v.closeSheet();
  assert(!v.sheetShown && v.pressedButton==='' && v.testSheetChanges.at(-1)===false, '关闭弹层同步释放按压并通知父页面');
}
console.log('4) 等待确认期间更换条目不会把旧确认应用到新条目');
{
  const v=newView();v.openDetail(v.data.checkIns[0]);let resolve;
  v.testDialogPromise=new Promise(done=>{resolve=done;});
  const pending=v.confirmAction('CHECKIN_DELETE','删除A','确认A','已删除');
  v.requestedItemId='b';v.openRequestedItem();resolve({index:1});await pending;
  assert(v.testActions.length===1 && v.testActions[0].id==='a', '异步确认始终操作打开对话框时的条目');
  assert(v.data.checkIns.length===1 && v.data.checkIns[0].id==='b', '永久删除不会误删确认期间新选中的计划');
  assert(v.sheetShown && v.selectedId==='b' && v.modal==='detail', '旧确认完成不关闭或改写当前其他条目的页面');
  assert(v.detailTitleFromView()==='计划B', '常驻详情切换 selectedId 后标题立即跟随新条目');
}
{
  const v=newView();v.openDetail(v.data.checkIns[0]);let resolve;
  v.testDialogPromise=new Promise(done=>{resolve=done;});
  const pending=v.confirmAction('CHECKIN_DELETE','删除A','确认A','已删除');
  v.openDetail(v.data.checkIns[1]);v.editSelected();resolve({index:1});await pending;
  assert(v.data.checkIns.length===1 && v.data.checkIns[0].id==='b', '新草稿打开期间旧删除确认仍只操作原条目');
  assert(v.selectedId==='b' && v.modal==='editor', '其他条目的确认完成不打断正在编辑的新草稿');
}
console.log('5) 实际半模态关闭拦截区分系统返回与直接关闭');
{
  let valid=true;
  for(const modal of ['editor','backfill','range','history']) {
    const v=newView();v.openDetail(v.data.checkIns[0]);v.showModal(modal);let dismisses=0;
    v.dismissSheet({reason:0,dismiss:()=>{dismisses++;}});
    valid=valid && v.modal==='detail' && v.sheetShown && v.selectedId==='a' && dismisses===0;
  }
  assert(valid, '有选中条目的所有二级页收到系统返回时只退回详情');
}
{
  const v=newView();v.openDetail(v.data.checkIns[0]);let dismisses=0;
  v.dismissSheet({reason:0,dismiss:()=>{dismisses++;}});
  assert(dismisses===1 && v.modal==='detail', '详情页系统返回交给原生弹层关闭一次');
}
{
  const v=newView();v.openNew();let dismisses=0;
  v.dismissSheet({reason:0,dismiss:()=>{dismisses++;}});
  assert(dismisses===1 && v.selectedId==='' && v.modal==='editor', '新建页系统返回直接关闭，不进入空详情');
}
{
  const v=newView();v.openDetail(v.data.checkIns[0]);v.editSelected();let dismisses=0;
  for(const reason of [1,2]) v.dismissSheet({reason,dismiss:()=>{dismisses++;}});
  assert(dismisses===2 && v.modal==='editor', '遮罩或下拉关闭原因不拦截为返回详情');
}
console.log('6) 新建与二级编辑分开转场，导航清理按钮按压');
{
  const v=newView();v.openNew();
  assert(v.editorTransitionFromView().identity===true,'新建表单只跟随半模态入场，不额外从右侧飞入');
  v.openDetail(v.data.checkIns[0]);v.editSelected();const transition=v.editorTransitionFromView();
  assert(transition.translate.x==='100%' && transition.animationOptions.motion==='spring',
    '从详情进入编辑继续使用横向弹簧转场');
  v.buttonTouch('checkin-edit',{type:TouchType.Down});let stateAtAction='unset';
  v.tapButton(()=>{stateAtAction=v.pressedButton;v.backToDetail();});
  assert(stateAtAction==='' && v.modal==='detail','管理按钮执行页面切换前同步清理按压状态');
  v.buttonTouch('checkin-backfill',{type:TouchType.Down});v.showModal('backfill');
  assert(v.pressedButton==='','非按钮路径切换二级页面也清空旧按压');
}
console.log('7) 打卡切换按钮真实触摸回调不依赖 Up 才复位');
{
  const button=new toggle.Class();let callbacks=0;let pressedAtToggle=true;
  button.onToggle=()=>{callbacks++;pressedAtToggle=button.pressed;};
  button.touchFromView({type:TouchType.Down});
  assert(button.pressed && button.testAnimations.at(-1).motion==='quick','切换按钮按下保持快速弹簧反馈');
  button.touchFromView({type:TouchType.Move});
  assert(button.pressed && callbacks===0,'触摸移动不误提交打卡或撤销');
  button.touchFromView({type:TouchType.Cancel});
  assert(!button.pressed && callbacks===0,'触摸取消复位而不调用业务动作');
  button.touchFromView({type:TouchType.Down});button.touchFromView({type:TouchType.Up});
  assert(!button.pressed && callbacks===0,'正常释放只复位，业务动作只由点击回调产生');
  button.touchFromView({type:TouchType.Down});button.clickFromView();
  assert(!button.pressed && !pressedAtToggle && callbacks===1,'丢失 Up 的点击也先复位再只调用一次业务回调');
  button.touchFromView({type:TouchType.Down});button.disappearFromView();
  assert(!button.pressed && callbacks===1,'按钮被删除或页面离场时不留下按压也不触发业务');
}
{
  const button=new toggle.Class();button.future=true;button.completed=true;button.pressed=true;let callbacks=0;
  button.onToggle=()=>{callbacks++;};button.touchFromView({type:TouchType.Down});
  assert(button.pressed && callbacks===0, '未来已完成按钮允许按压，触摸本身不提前执行撤销');
  button.clickFromView();button.touchFromView({type:TouchType.Up});
  assert(callbacks===1 && !button.pressed, '未来已完成按钮点击提交一次撤销并清理按压，随后释放不重复提交');
  button.completed=false;button.touchFromView({type:TouchType.Down});button.clickFromView();
  assert(callbacks===2 && !button.pressed, '同一组件撤销后可再次点击提前打卡');
  button.completed=true;button.future=false;button.touchFromView({type:TouchType.Down});button.clickFromView();
  assert(callbacks===3 && !button.pressed, '日期到达当期后继续保持相同撤销交互');
}
console.log('8) 四种二级输入的焦点跟随只滚动本页控制器');
{
  const v=newView();v.sheetActive=true;v.testDensity=2;
  const node=(top,height)=>({isAttached:()=>true,getPositionToWindowWithTransform:()=>({y:top}),getMeasuredSize:()=>({height:height*2})});
  v.testNodes=new Map([['field',node(180,60)],['checkin-editor-scroll',node(100,100)],
    ['checkin-backfill-scroll',node(100,100)],['checkin-range-scroll',node(100,100)],['checkin-history-scroll',node(100,100)]]);
  for(const modal of ['editor','backfill','range','history']) {
    v.showModal(modal);v.focusedInput='field';v.ensureFocusedInputVisible();
  }
  assert([v.editorScroller,v.backfillScroller,v.rangeScroller,v.historyRecordScroller].every(scroller=>scroller.calls?.length===1 && scroller.calls[0][1]===48),
    '编辑、补卡、确认内容与历史计划分别滚动各自控制器到真实输入框可见位置');
  assert(!v.detailScroller.calls && !v.overviewScroller.calls,'焦点跟随不移动常驻详情和背景列表');
  v.showModal('detail');v.ensureFocusedInputVisible();
  assert(!v.detailScroller.calls,'返回详情清空输入焦点后不继续滚动');
}
console.log('9) 时间线实际列表参数、加载历史锚点与过期帧隔离');
{
  const v=newView();const older=modelApi.addDays(v.today(),-100);
  for(const item of v.data.checkIns)item.startDate=older;
  v.openDetail(v.data.checkIns[0]);
  const options=v.timelineOptionsFromView();const ordered=v.orderedTimeline();
  assert(options.scroller===v.timelineScroller && options.initialIndex===ordered.findIndex(record=>record.key===v.today())+1,
    'List实际挂载时间线专用控制器，初始索引含历史入口并定位今天');
  const nesting=v.timelineNestingFromView();
  assert(nesting.scrollForward==='parent-first' && nesting.scrollBackward==='self-first',
    '实际List嵌套选项使向后先滚外层，向历史方向先滚时间线');
  const anchor=v.selectedTimeline.at(-1).key;const originalLength=v.selectedTimeline.length;const before=JSON.stringify(v.data);
  v.moreTimelineHistory();const pending=v.testFrames.at(-1);pending.callback();
  const restored=v.timelineScroller.indexCalls?.at(-1);
  assert(v.selectedTimeline.length>originalLength && restored.index===v.orderedTimeline().findIndex(record=>record.key===anchor)+1 && restored.smooth===false && restored.align==='start',
    '加载更早记录后下一帧回到原最早记录，补入记录不会把阅读位置移到最开头');
  assert(JSON.stringify(v.data)===before, '加载与滚动历史只修改派生列表，不修改持久数据');
}
{
  const v=newView();for(const item of v.data.checkIns)item.startDate=modelApi.addDays(v.today(),-100);
  v.openDetail(v.data.checkIns[0]);v.moreTimelineHistory();const pending=v.testFrames.at(-1);
  v.openDetail(v.data.checkIns[1]);pending.callback();
  assert(!v.timelineScroller.indexCalls, '加载历史期间切换计划后，旧帧不能滚动新计划同日期记录');
  v.moreTimelineHistory();const inDetail=v.testFrames.at(-1);v.showModal('history');inDetail.callback();
  assert(!v.timelineScroller.indexCalls, '进入历史子页后旧列表帧不移动底层详情');
  v.backToDetail();v.moreTimelineHistory();const beforeClose=v.testFrames.at(-1);v.closeSheet();beforeClose.callback();
  assert(!v.timelineScroller.indexCalls, '关闭弹层后未提交的时间线帧不再执行滚动');
}
console.log('10) 材质容器内容回调必须绑定显式 Builder，避免空分支运行时链式调用');
// 用 TypeScript 词法/语法树检查实际属性回调。不能用“源码含 emptyHistory”代替绑定验证：
// 在普通箭头回调中 Text(...).fontSize(...) 会被当成普通调用，ArkTS 静态检查仍可能放行。
function materialContentBindings(text, filename) {
  const builders=new Set([...text.matchAll(/@Builder\s+(?:(?:private|public|protected)\s+)?(\w+)\s*\(/g)].map(value=>value[1]));
  const bindings=[];const issues=[];
  // 从每个实际调用起点单独扫描，避免整份 ArkUI 文件中的模板字符串需要 parser 重扫而跳过后续调用。
  for(const match of text.matchAll(/\b(MaterialSection|MaterialButtonScope)\s*\(/g)) {
    const scanner=ts.createScanner(ts.ScriptTarget.Latest,true,ts.LanguageVariant.Standard,text.slice(match.index));
    let depth=0;let end=0;
    while(true) {
      const kind=scanner.scan();if(kind===ts.SyntaxKind.EndOfFileToken)break;
      if(kind===ts.SyntaxKind.OpenParenToken)depth++;
      if(kind===ts.SyntaxKind.CloseParenToken && --depth===0){end=scanner.getTextPos();break;}
    }
    const location=filename+':'+((text.slice(0,match.index).match(/\n/g)?.length||0)+1);
    const callSource=text.slice(match.index,match.index+end);
    const ast=ts.createSourceFile(filename,'const material = '+callSource+';',ts.ScriptTarget.Latest,true,ts.ScriptKind.TS);
    const call=ast.statements[0]?.declarationList?.declarations[0]?.initializer;
    const properties=call && ts.isCallExpression(call) && call.arguments[0] && ts.isObjectLiteralExpression(call.arguments[0]) ? call.arguments[0].properties : [];
    const property=properties.find(value=>ts.isPropertyAssignment(value) && value.name.getText(ast)==='content');
    const content=property?.initializer;
    if(ast.parseDiagnostics.length || !content || !ts.isArrowFunction(content)) {issues.push(location+'：content 不是可解析的 Builder 回调');continue;}
    const expressions=ts.isBlock(content.body) ? content.body.statements.map(statement=>ts.isExpressionStatement(statement)?statement.expression:null) : [content.body];
    const targets=[];
    for(const expression of expressions) {
      const callee=expression && ts.isCallExpression(expression)?expression.expression:null;
      if(!callee || !ts.isPropertyAccessExpression(callee) || callee.expression.kind!==ts.SyntaxKind.ThisKeyword || !builders.has(callee.name.text)) {
        issues.push(location+'：content 必须调用同组件已声明的 @Builder 方法');
      } else targets.push(callee.name.text);
    }
    if(expressions.length===0)issues.push(location+'：content 为空');
    bindings.push({filename,location,targets,callback:content.getText(ast)});
  }
  return {bindings,issues};
}
function arktsFiles(directory) {
  return readdirSync(directory,{withFileTypes:true}).flatMap(entry=>entry.isDirectory()?arktsFiles(path.join(directory,entry.name)):
    entry.name.endsWith('.ets')?[path.join(directory,entry.name)]:[]);
}
{
  const audits=arktsFiles(path.join(root,'entry/src/main/ets')).map(filename=>materialContentBindings(readFileSync(filename,'utf8'),filename));
  const bindings=audits.flatMap(value=>value.bindings);const issues=audits.flatMap(value=>value.issues);
  assert(bindings.length>0 && issues.length===0,'全部 '+bindings.length+' 个材质容器内容回调均调用本组件显式 Builder'+(issues.length?'：'+issues.join('; '):''));
  const empty=bindings.find(value=>value.filename.endsWith('CheckInView.ets') && value.targets.includes('emptyHistory'));
  assert(!!empty && empty.targets.length===1,'空历史 MaterialSection 的实际 content 只绑定 emptyHistory Builder');
  let invoked=0;const owner={emptyHistory(){invoked++;}};
  const factory=vm.runInNewContext('(function(){return ('+empty.callback+');})');factory.call(owner)();
  assert(invoked===1,'直接执行真实空历史内容回调只调用 Builder，不执行未绑定的 Text 链');
  const inline=viewSource.replace(empty.callback,"() => { Text('暂无记录').fontSize(14); }");
  assert(materialContentBindings(inline,'inline-regression.ets').issues.length>0,
    '在内存中恢复旧的内联 Text 链时，绑定检查能实际拦截该回归');
  const unbound=viewSource.replace('@Builder private emptyHistory()', 'private emptyHistory()');
  assert(materialContentBindings(unbound,'unbound-regression.ets').issues.length>0,
    '移除被调用方法的 Builder 装饰器也会被检查拦截');
}
console.log(`Check-in navigation regression: ${passed} assertions passed.`);
