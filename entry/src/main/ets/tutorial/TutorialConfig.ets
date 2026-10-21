// 一页使用说明集中配置；新增或调整功能时只需更新这里的简要文案。
export const TUTORIAL_VERSION: number = 3;
export class TutorialFeature {
  id: string;
  icon: string;
  title: string;
  description: string;
  constructor(id: string, icon: string, title: string, description: string) {
    this.id = id; this.icon = icon; this.title = title; this.description = description;
  }
}
export const TUTORIAL_TITLE: string = '让计划，轻一点';
export const TUTORIAL_SUBTITLE: string = '几件小事，开始用好序笺';
export const TUTORIAL_FOOTNOTE: string = '本机自动保存 · 随时在「设置 → 新手教程」回看';
const FEATURES: TutorialFeature[] = [
  new TutorialFeature('plan', 'calendar', '今天与未来，分开安排', '点分区右侧 ＋ 添加日程；未来计划需选择截止日期，到期自动进入当日。'),
  new TutorialFeature('edit', 'edit', '记录进度，轻勾完成', '右侧编辑，左侧勾选完成；编辑页也可设置进度或删除日程。'),
  new TutorialFeature('drag', 'move', '长按拖动，随手整理', '长按卡片可排序、跨区移动；拖动中间分割条，调整两区大小。'),
  new TutorialFeature('group', 'check', '按分组，让列表更清楚', '在设置中开启分组，再到新增或编辑页选择分组；长按组标题可整组排序。'),
  new TutorialFeature('settings', 'settings', '历史和外观，都在设置', '已完成日程归入历史，可查看或恢复；主题与配色也能按喜好调整。')
];
export function tutorialFeatures(): TutorialFeature[] { return FEATURES.slice(); }
export class TutorialProgress {
  version: number = TUTORIAL_VERSION;
  status: string = 'new';
}
export function normalizeTutorial(raw: TutorialProgress): TutorialProgress {
  const progress = new TutorialProgress();
  if (!raw || raw.version !== TUTORIAL_VERSION) return progress;
  progress.status = raw.status === 'completed' ? 'completed' : 'new';
  return progress;
}
export function shouldAutoTutorial(progress: TutorialProgress): boolean {
  return tutorialFeatures().length > 0 && normalizeTutorial(progress).status === 'new';
}
export function closeTutorial(progress: TutorialProgress): TutorialProgress {
  const next = normalizeTutorial(progress);
  next.status = 'completed';
  return next;
}
