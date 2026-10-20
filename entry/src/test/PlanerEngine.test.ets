import { describe, it, expect } from '@ohos/hypium';
import { AppAction, AppData } from '../main/ets/model/PlanerModel';
import { freshData, reduce, normalizeData } from '../main/ets/model/PlanerEngine';

function add(data: AppData, text: string, section: string = 'today'): AppData {
  const action = new AppAction('ADD_TASK');
  action.text = text;
  action.section = section;
  if (section === 'future') action.dueDate = '2026-08-30';
  return reduce(data, action);
}

export default function planerEngineTest() {
  describe('PlanerEngine', () => {
    it('完成当日后次日归档且未完成顺延', 0, () => {
      let data = freshData();
      data.currentDate = '2026-08-24';
      data = add(data, '完成任务');
      data = add(data, '保留任务');
      const complete = new AppAction('TOGGLE_TODAY');
      complete.id = data.todayTasks[0].id;
      data = reduce(data, complete);
      data = reduce(data, new AppAction('END_DAY'));
      expect(data.currentDate).assertEqual('2026-08-25');
      expect(data.todayTasks[0].text).assertEqual('保留任务');
      expect(data.history[0].tasks[0].plannedDate).assertEqual('2026-08-24');
    });
    it('未来日程完成立即归档并恢复', 0, () => {
      let data = freshData();
      data.currentDate = '2026-08-24';
      data = add(data, '未来任务', 'future');
      const id = data.futureTasks[0].id;
      const complete = new AppAction('COMPLETE_FUTURE');
      complete.id = id;
      data = reduce(data, complete);
      expect(data.futureTasks.length).assertEqual(0);
      expect(data.history[0].tasks[0].plannedDate).assertEqual('2026-08-30');
      const restore = new AppAction('RESTORE');
      restore.entryDate = '2026-08-24';
      restore.id = id;
      restore.target = 'future';
      data = reduce(data, restore);
      expect(data.futureTasks[0].completed).assertFalse();
      expect(data.futureTasks[0].dueDate).assertEqual('2026-08-30');
    });
    it('修改进度与不可变状态', 0, () => {
      let data = freshData();
      data = add(data, '任务');
      const action = new AppAction('EDIT_TASK');
      action.id = data.todayTasks[0].id;
      action.text = '新名称';
      action.progress = 100;
      const updated = reduce(data, action);
      expect(updated.todayTasks[0].completed).assertTrue();
      expect(data.todayTasks[0].text).assertEqual('任务');
      action.progress = 40;
      const resumed = reduce(updated, action);
      expect(resumed.todayTasks[0].completed).assertFalse();
    });
    it('空分组目录持久化与显式删除', 0, () => {
      let data = freshData();
      const action = new AppAction('ADD_TASK');
      action.text = '学习';
      action.group = '学习组';
      data = reduce(data, action);
      const remove = new AppAction('DELETE_TASK');
      remove.id = data.todayTasks[0].id;
      data = reduce(data, remove);
      data = normalizeData(JSON.parse(JSON.stringify(data)) as AppData);
      expect(data.groups[0]).assertEqual('学习组');
      const removeGroup = new AppAction('DELETE_GROUP');
      removeGroup.group = '学习组';
      data = reduce(data, removeGroup);
      expect(data.groups.length).assertEqual(0);
    });
    it('日期前进后回退保留隐藏区间', 0, () => {
      let data = freshData();
      data.currentDate = '2026-08-24';
      data = add(data, '未来任务', 'future');
      const forward = new AppAction('ROLLOVER_TO');
      forward.key = '2026-08-30';
      data = reduce(data, forward);
      expect(data.todayTasks.length).assertEqual(1);
      const back = new AppAction('ROLLBACK_TO');
      back.key = '2026-08-24';
      data = reduce(data, back);
      expect(data.futureTasks[0].dueDate).assertEqual('2026-08-30');
      expect(data.futureTasks[0].startDate).assertEqual('2026-08-25');
    });
  });
}
