// 提取真实 Index 半模态方法并连接真实 reducer；不渲染界面、不访问设备或用户数据。
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
const root=path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const require=createRequire(import.meta.url);
let ts;
for(const candidate of [process.env.TYPESCRIPT_PATH,'typescript',path.join(root,'../Planer/node_modules/typescript'),
  'D:/Software/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'].filter(Boolean)) {
  try {ts=require(candidate);break;} catch {}
}
if(!ts)throw new Error('请设置 TYPESCRIPT_PATH 指向已有 TypeScript 模块。');
function compile(source,filename) {
  const result=ts.transpileModule(source,{fileName:filename,compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021},reportDiagnostics:true});
  const errors=(result.diagnostics||[]).filter(value=>value.category===ts.DiagnosticCategory.Error);
  if(errors.length)throw new Error(errors.map(value=>value.messageText).join('\n'));
  return result.outputText;
}
const modules=new Map();
function model(name) {
  if(modules.has(name))return modules.get(name);
  const filename=path.join(root,'entry/src/main/ets/model',name+'.ets');
  const module={exports:{}};modules.set(name,module.exports);
  vm.runInThisContext('(function(require,module,exports){'+compile(readFileSync(filename,'utf8'),filename)+'\n})',
    {filename})(request=>model(path.basename(request)),module,module.exports);
  return module.exports;
}
const modelApi={...model('PlanerModel'),...model('PlanerEngine')};
const source=readFileSync(path.join(root,'entry/src/main/ets/pages/Index.ets'),'utf8');
function method(name) {
  const start=source.indexOf('  private '+name+'(');
  if(start<0)throw new Error('缺少真实方法：'+name);
  const begin=source.indexOf('{',start);let depth=1;
  for(let index=begin+1;index<source.length;index++) {
    if(source[index]==='{')depth++;
    if(source[index]==='}'&&--depth===0)return source.slice(start,index+1);
  }
  throw new Error('方法未闭合：'+name);
}
const names=['openModal','closeModal','sheetHeight','modalButtonTouch','modalTap','selectBrowsingDate',
  'selectRestoreTarget','restoreTask','restoreSelected','openEditor','markedDates'];
const appearance=readFileSync(path.join(root,'entry/src/main/ets/theme/Appearance.ets'),'utf8');
const feedback=appearance.slice(appearance.indexOf('export class ButtonFeedback'),appearance.indexOf('const controlMaterials:'))
  .replace('export class','class');
const TouchType={Down:0,Up:1,Move:2,Cancel:3};
let refreshes=0;
const context=vm.createContext({...modelApi,TouchType,SheetSize:{FIT_CONTENT:'fit'},
  Motion:{quick:()=>({kind:'quick'}),spring:()=>({kind:'spring'})},
  EditorMaterialRefresh:{request:()=>{refreshes++;}}});
vm.runInContext(compile(feedback+'\nclass Harness {\n'+names.map(method).join('\n')+
  '\n}\nglobalThis.Harness=Harness;','Index-sheet-harness.ts'),context);
function fixture() {
  const page=new context.Harness();page.data=modelApi.freshData();
  page.data.currentDate=page.data.lastRolloverDate=modelApi.todayKey();
  page.modal='';page.sheetShown=false;page.modalPressedButton='';page.viewportWidth=400;
  page.restoreTarget='today';page.restoreDate='';page.selectedTask=new modelApi.Task();
  page.actions=[];page.animations=[];page.edgeStops=0;
  page.stopEdgeScroll=()=>{page.edgeStops++;};page.navigate=number=>{page.page=number;};
  page.getUIContext=()=>({animateTo:(options,change)=>{page.animations.push(options);change();if(options.onFinish)options.onFinish();}});
  page.dispatch=action=>{page.actions.push(action);page.data=modelApi.reduce(page.data,action);};
  return page;
}
function history(page,plannedDate=null) {
  const task=new modelApi.Task();task.id='archived';task.text='需要恢复的日程';task.completed=true;task.plannedDate=plannedDate;
  const entry=new modelApi.HistoryEntry();entry.date=modelApi.addDays(page.data.currentDate,-2);entry.tasks=[task];
  page.data.history=[entry];return {task,date:entry.date};
}
let passed=0;
function assert(condition,message){if(!condition)throw new Error(message);passed++;console.log('✓ '+message);}
console.log('1) 统一半模态高度与开关、按压生命周期');
{
  const p=fixture();
  assert(['add','edit','move','date','restore'].every(modal=>{p.modal=modal;return p.sheetHeight()==='84%';}),
    '全部非教程表单在手机上采用统一可滚动高度');
  p.viewportWidth=800;
  assert(['add','edit','move','date','restore'].every(modal=>{p.modal=modal;return p.sheetHeight()==='90%';}),
    '全部非教程表单在宽屏上采用统一可滚动高度');
  p.modal='';assert(p.sheetHeight()==='fit','未打开表单时保留原生内容高度回退');
  p.modalPressedButton='old';p.openModal('date');
  assert(p.sheetShown&&p.modal==='date'&&p.modalPressedButton===''&&p.edgeStops===1,'打开日期表单停止边缘滚动并清理旧按压');
  p.modalButtonTouch('date-return-today',{type:TouchType.Down});
  assert(p.modalPressedButton==='date-return-today','材质按钮按下保留可控反馈');
  p.modalButtonTouch('date-return-today',{type:TouchType.Cancel});
  assert(p.modalPressedButton==='','触摸被取消时清理按钮状态');
  p.modalButtonTouch('date-return-today',{type:TouchType.Down});let atTap='unset';
  p.modalTap(()=>{atTap=p.modalPressedButton;p.closeModal();});
  assert(atTap===''&&!p.sheetShown,'操作先清理按压再关闭半模态');
}
console.log('2) 日期浏览只派发选择日期且沿用预览语义');
{
  const p=fixture();const task=new modelApi.Task();task.id='today-done';task.text='今日已完成';task.completed=true;
  p.data.todayTasks=[task];p.openModal('date');const target=modelApi.addDays(p.data.currentDate,3);
  p.selectBrowsingDate(target);
  assert(p.actions.length===1&&p.actions[0].type==='SELECT_DATE'&&p.actions[0].key===target&&!p.sheetShown,
    '选择日期只提交一次浏览动作并关闭表单');
  assert(p.data.currentDate===target&&p.data.history.length===0,'浏览未来不会提前归档今天完成项');
  p.openModal('date');p.selectBrowsingDate(modelApi.todayKey());
  assert(p.data.currentDate===modelApi.todayKey()&&p.actions.length===2&&!p.sheetShown,'回到今天沿用同一动作并关闭表单');
}
console.log('3) 恢复位置展开保持草稿且仅在确认时提交');
{
  const p=fixture();const original=history(p);p.restoreTask(original.task,original.date);
  assert(p.sheetShown&&p.modal==='restore'&&p.selectedTask.id===original.task.id&&p.selectedHistoryDate===original.date,
    '过期历史任务打开恢复表单并保留来源定位');
  assert(p.restoreTarget==='today'&&p.restoreDate===modelApi.addDays(p.data.currentDate,1)&&p.actions.length===0,
    '恢复表单默认当日并准备次日草稿，不提前恢复');
  const count=p.animations.length;const beforeRefresh=refreshes;p.selectRestoreTarget('today');
  assert(p.animations.length===count,'重复选择恢复位置不重复展开动画');
  p.selectRestoreTarget('future');
  assert(p.restoreTarget==='future'&&p.animations.at(-1).kind==='spring'&&refreshes===beforeRefresh+1,
    '展开恢复日期经过真实弹簧动画并在结束后刷新卡片材质');
  const draft=modelApi.addDays(p.data.currentDate,5);p.restoreDate=draft;p.selectRestoreTarget('today');p.selectRestoreTarget('future');
  assert(p.restoreDate===draft&&p.actions.length===0,'恢复位置往返切换保留日期草稿且不写业务数据');
  p.restoreSelected();
  assert(p.actions.length===1&&p.actions[0].type==='RESTORE'&&p.actions[0].entryDate===original.date&&p.actions[0].dueDate===draft,
    '未来恢复提交原历史来源与用户选择日期');
  assert(!p.sheetShown&&p.data.futureTasks.some(task=>task.id===original.task.id&&task.dueDate===draft&&!task.completed),
    '确认后日程进入未来并关闭表单');
}
{
  const p=fixture();const original=history(p);p.restoreTask(original.task,original.date);p.restoreSelected();
  assert(p.actions[0].target==='today'&&p.actions[0].dueDate===null&&p.data.todayTasks.some(task=>task.id===original.task.id),
    '当日恢复不夹带未使用的未来日期草稿');
}
{
  const p=fixture();const future=modelApi.addDays(p.data.currentDate,3);const original=history(p,future);p.restoreTask(original.task,original.date);
  assert(p.actions.length===1&&p.actions[0].dueDate===future&&!p.sheetShown,'有效原计划日期仍直接恢复，不强制打开新增表单');
}
console.log('4) 普通编辑与打卡入口复用保持不变');
{
  const p=fixture();const task=new modelApi.Task();task.id='future';p.openEditor('future',task);
  assert(p.modal==='edit'&&p.editorSection==='future'&&p.selectedTask===task&&p.selectedTarget===0,
    '普通未来日程继续进入原 TaskEditor 编辑流程');
  p.closeModal();p.openEditor('today');
  assert(p.modal==='add'&&p.editorSection==='today'&&p.selectedTask.id==='','普通新建继续交给 TaskEditor 草稿');
  p.closeModal();task.checkInId='checkin-a';p.checkInRequestRevision=2;p.openEditor('today',task);
  assert(!p.sheetShown&&p.page===1&&p.checkInRequestedId==='checkin-a'&&p.checkInRequestRevision===3,
    '关联打卡日程仍转向打卡详情，不误开普通编辑器');
}
console.log(`Index sheet regression: ${passed} assertions passed.`);
