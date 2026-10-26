// 执行真实历史周期页面方法、@Watch 与领域校验/reducer，不渲染界面或访问设备数据。
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
const project=path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const require=createRequire(import.meta.url);
let ts;
for(const candidate of [process.env.TYPESCRIPT_PATH,'typescript',path.join(project,'../Planer/node_modules/typescript'),
  'D:/Software/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'].filter(Boolean)) {
  try {ts=require(candidate);break;} catch {}
}
if(!ts)throw new Error('请设置 TYPESCRIPT_PATH 指向本机已有 TypeScript。');
function compile(source,filename) {
  const result=ts.transpileModule(source,{fileName:filename,compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021},reportDiagnostics:true});
  const errors=(result.diagnostics||[]).filter(value=>value.category===ts.DiagnosticCategory.Error);
  if(errors.length)throw new Error(errors.map(value=>value.messageText).join('\n'));
  return result.outputText;
}
const modules=new Map();
function loadModel(name) {
  if(modules.has(name))return modules.get(name);
  const filename=path.join(project,'entry/src/main/ets/model',name+'.ets');
  const module={exports:{}};modules.set(name,module.exports);
  vm.runInThisContext('(function(require,module,exports){'+compile(readFileSync(filename,'utf8'),filename)+'\n})',{filename})(
    request=>loadModel(path.basename(request)),module,module.exports);
  return module.exports;
}
const api={...loadModel('PlanerModel'),...loadModel('CheckInModel'),...loadModel('PlanerEngine'),...loadModel('CheckInEngine')};
const filename=path.join(project,'entry/src/main/ets/components/CheckInHistoryRecord.ets');
const source=readFileSync(filename,'utf8');
const core=source.slice(source.indexOf('@Component'),source.indexOf('  @Builder'));
const watches=[...core.matchAll(/@Watch\('([^']+)'\)\s+(?:private\s+)?(\w+)/g)].map(value=>({method:value[1],field:value[2]}));
const code=core.replace('@Component','').replace('export struct CheckInHistoryRecord','class HistoryPage')
  .replace(/@Watch\('[^']+'\)\s*/g,'').replace(/@(?:Prop|State)\s+/g,'')+
  '\ngetUIContext(){return {animateTo:(_,change)=>change()};}\n}\nglobalThis.HistoryPage=HistoryPage;';
let refreshes=0;
const context=vm.createContext({...api,Palette:class{},Scroller:class{},EditorMaterialRefresh:{request:()=>{refreshes++;}}});
vm.runInContext(compile(code,filename),context);
function installWatches(instance) {
  for(const binding of watches) {
    let value=instance[binding.field];Object.defineProperty(instance,binding.field,{configurable:true,get:()=>value,
      set(next){if(Object.is(next,value))return;value=next;instance[binding.method]();}});
  }
}
function action(type,page,name) {const result=new api.AppAction(type);result.id=page.itemId;result.key=page.keyDate;if(name!==undefined)result.text=name;return result;}
function fixture(recordFields={}) {
  const page=new context.HistoryPage();installWatches(page);
  page.backCalls=0;page.closeCalls=0;page.blurCalls=[];page.viewportCalls=0;page.actions=[];
  page.onBack=()=>{page.backCalls++;};page.onClose=()=>{page.closeCalls++;};
  page.onInputBlur=id=>page.blurCalls.push(id);page.onViewportChange=()=>{page.viewportCalls++;};
  const data=new api.AppData();data.currentDate=data.lastRolloverDate='2026-10-27';
  data.checkIns=[Object.assign(new api.CheckInItem(),{id:'words',name:'背单词999-1008',startDate:'2026-10-20',autoIncrement:true,step:10})];
  if(recordFields!==null)data.checkInRecords=[Object.assign(new api.CheckInRecord(),{itemId:'words',key:'2026-10-24',
    name:'背单词21-30',status:'ready',generatedAt:'2026-10-24T00:00:00.000Z'},recordFields)];
  page.data=data;page.itemId='words';page.keyDate='2026-10-24';
  page.onUndo=()=>{const value=action('CHECKIN_UNDO',page);page.actions.push(value);page.data=api.reduce(page.data,value);return '';};
  page.onBackfill=name=>{const value=action('CHECKIN_BACKFILL',page,name);page.actions.push(value);page.data=api.reduce(page.data,value);return '';};
  page.aboutToAppear();return page;
}
let passed=0;
function assert(condition,message){if(!condition)throw new Error(message);passed++;console.log('✓ '+message);}
console.log('1) 历史名称只读，补卡撤销均留在当期');
{
  const p=fixture();
  assert(p.historicalName()==='背单词21-30'&&!p.needsName()&&p.canSubmit(),'已有周期显示原始名称，不借用当前计划数字');
  p.draftName='试图覆盖历史';p.submit();
  assert(p.actions[0].type==='CHECKIN_BACKFILL'&&p.actions[0].text==='背单词21-30','提交忽略草稿覆盖，沿用真实历史快照');
  assert(p.completed()&&p.statusText()==='已补卡'&&p.completionTime().length>0,'同步回传完成状态、补卡标记和完成时间');
  assert(p.backCalls===0&&p.closeCalls===0&&p.keyDate==='2026-10-24'&&!p.awaitingRefresh,'成功留在当期且同步刷新不留下提交锁');
  p.submit();
  assert(p.actions[1].type==='CHECKIN_UNDO'&&!p.completed()&&p.historicalName()==='背单词21-30','直接撤销保留原始历史名称');
  assert(p.statusText()==='未完成'&&p.completionTime()===''&&p.canSubmit(),'撤销后清除完成信息并允许再次补卡');
  p.submit();assert(p.completed()&&p.actions[2].text==='背单词21-30','再次补卡仍提交相同历史名称');
}
console.log('2) 未生成与旧待确认周期要求实际内容');
{
  const p=fixture(null);
  assert(p.needsName()&&p.draftName===''&&!p.canSubmit(),'缺少快照只给空输入，不预填今天的内容');
  p.submit();assert(p.error.includes('当日实际')&&p.actions.length===0,'空白历史内容阻止补卡');
  p.draftName='   ';p.submit();assert(p.actions.length===0,'全空格也不会生成历史记录');
  p.draftName='  实际完成第7课  ';p.submit();
  assert(p.actions[0].text==='实际完成第7课'&&p.historicalName()==='实际完成第7课'&&!p.needsName(),'填写的实际历史内容去首尾空白并变为只读快照');
  assert(p.data.checkIns[0].name==='背单词999-1008','补卡不会反推或改写今天的递增名称');
}
{
  const p=fixture({status:'pending',name:''});p.draftName='当日实际内容';p.submit();
  assert(p.completed()&&p.actions.length===1,'数字溢出等旧pending周期可按领域校验补记');
  const named=fixture({status:'pending',name:'旧版第5次'});named.submit();
  assert(named.completed()&&named.historicalName()==='旧版第5次','有名称的pending快照仍只读并可补卡');
}
console.log('3) 日期与计划范围限制');
{
  const p=fixture();p.keyDate='2026-10-27';p.submit();
  assert(!p.canSubmit()&&p.actions.length===0&&p.error.includes('过去'),'今天不能从历史页操作');
  p.keyDate='2026-10-28';p.submit();assert(!p.canSubmit()&&p.actions.length===0,'未来日期不能通过历史页提前完成或撤销');
  p.keyDate='2026-02-30';p.submit();assert(p.error.includes('日期')&&p.actions.length===0,'不存在的日期不能绕过领域校验');
  p.keyDate='2026-10-24';const data=p.data.clone();data.checkIns=[];p.data=data;p.submit();
  assert(!p.canSubmit()&&p.error.includes('不存在')&&p.actions.length===0,'计划已删除时仅能查看遗留快照，不能提交');
}
{
  const p=fixture(null);p.keyDate='2026-10-19';p.draftName='无效周期';p.submit();
  assert(!p.canSubmit()&&p.error.includes('周期')&&p.actions.length===0,'开始日期之前的无快照记录不可补卡');
  p.keyDate='2026-10-24';const data=p.data.clone();data.checkIns[0].pauses=[Object.assign(new api.CheckInPause(),{from:'2026-10-23',to:'2026-10-25'})];p.data=data;
  assert(!p.needsName()&&!p.canSubmit(),'暂停区间内未生成的日期保持不可操作');
}
{
  const p=fixture();const data=p.data.clone();data.checkIns[0].startDate='2026-10-26';p.data=data;p.submit();
  assert(p.completed()&&p.historicalName()==='背单词21-30','改过计划开始日期后已有历史快照仍按实际周期补卡');
}
console.log('4) 外部刷新、草稿与错误保留');
{
  const p=fixture(null);p.draftName='尚未提交';p.error='保存失败';p.data=p.data.clone();
  assert(p.draftName==='尚未提交'&&p.error==='保存失败','无关数据刷新不会丢失草稿或清除失败提示');
  const data=p.data.clone();data.checkInRecords=[Object.assign(new api.CheckInRecord(),{itemId:'words',key:p.keyDate,name:'外部已完成第4课',
    status:'completed',advanced:true,completedAt:'2026-10-23T02:30:00.000Z'})];p.data=data;
  assert(p.historicalName()==='外部已完成第4课'&&p.draftName===''&&!p.needsName(),'外部快照出现时立即锁定真实名称，丢弃未提交覆盖草稿');
  assert(p.statusText()==='已提前打卡'&&p.error===''&&p.canSubmit(),'过去的提前完成记录显示标记，允许按历史规则撤销');
  p.submit();assert(!p.completed()&&p.historicalName()==='外部已完成第4课','撤销外部完成记录仍保留其快照');
}
{
  const p=fixture(null);p.draftName='保留的历史内容';p.onBackfill=()=> '模拟存储失败';p.submit();
  assert(p.error==='模拟存储失败'&&p.draftName==='保留的历史内容'&&p.canSubmit()&&!p.submitting,'回调失败留页保留输入，解除提交锁允许重试');
  p.onBackfill=()=>{throw new Error('失败');};p.submit();
  assert(p.error==='操作未完成，请重试'&&!p.submitting&&!p.awaitingRefresh,'异常回调转换为错误反馈，不遗留锁');
  p.keyDate='2026-10-25';
  assert(p.draftName===''&&p.error===''&&p.needsName(),'切换历史身份时不把旧日期草稿带入新周期');
}
console.log('5) 延迟回传与重复提交保护');
{
  const p=fixture();let calls=0;p.onBackfill=()=>{calls++;p.submit();return '';};p.submit();p.submit();
  assert(calls===1&&p.awaitingRefresh&&!p.canSubmit(),'重入和父级快照未回传期间不重复派发补卡');
  p.data=api.reduce(p.data,action('CHECKIN_BACKFILL',p,p.historicalName()));
  assert(p.completed()&&!p.awaitingRefresh&&p.canSubmit(),'父级新记录回传后解除等待并提供撤销操作');
}
{
  const p=fixture();p.data.checkInRecords[0].status='completed';p.data.checkInRecords[0].completedAt='2026-10-24T10:00:00Z';p.submit();
  assert(p.actions[0].type==='CHECKIN_UNDO','提交前读取最新真实record，避免以缓存状态重复补卡');
}
console.log('6) 完成标记与离场焦点清理');
{
  const p=fixture({status:'completed',backfilled:false,advanced:false,completedAt:'not-a-date'});
  assert(p.statusText()==='已完成'&&p.completionTime()==='not-a-date','普通完成与异常时间字符串安全展示');
  const before=p.blurCalls.length;p.pressedButton='submit';p.aboutToDisappear();
  assert(p.pressedButton===''&&p.blurCalls.length===before+1&&p.blurCalls.at(-1)==='checkin-history-name','历史页离场清理按压并通知宿主注销输入焦点');
  assert(refreshes>0&&p.viewportCalls>0&&p.backCalls===0&&p.closeCalls===0,'数据与布局刷新请求材质采样，不擅自导航');
}
console.log(`Check-in history regression: ${passed} assertions passed.`);
