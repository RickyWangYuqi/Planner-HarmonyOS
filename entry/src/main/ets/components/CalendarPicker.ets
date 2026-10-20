import { Palette } from '../theme/Theme';
import { Materials, Motion } from '../theme/Appearance';
import { fromKey, todayKey } from '../model/PlanerEngine';
import { IconButton } from './IconButton';

@Component
export struct PlanerCalendar {
  @Prop @Watch('syncMonth') value: string = '';
  @Prop @Watch('minimumChanged') minDate: string = '';
  @Prop marks: string[] = [];
  @Prop palette: Palette = new Palette();
  onSelect: (key: string) => void = (_key: string): void => {};
  @State private year: number = new Date().getFullYear();
  @State private month: number = new Date().getMonth();
  private week: string[] = ['一', '二', '三', '四', '五', '六', '日'];
  private rows: number[] = [0, 1, 2, 3, 4, 5];
  private columns: number[] = [0, 1, 2, 3, 4, 5, 6];

  aboutToAppear(): void {
    this.syncMonth();
  }

  private syncMonth(): void {
    const key = this.value && (!this.minDate || this.value >= this.minDate) ? this.value :
      (this.minDate > todayKey() ? this.minDate : todayKey());
    const date = fromKey(key);
    this.year = date.getFullYear();
    this.month = date.getMonth();
  }

  private minimumChanged(): void {
    // 起始日期跨月时，尚未选择的截止日历跟随到可选月份。
    if (!this.value || this.value < this.minDate) this.syncMonth();
  }

  private moveMonth(offset: number): void {
    const date = new Date(this.year, this.month + offset, 1);
    this.getUIContext().animateTo(Motion.quick(), () => {
      this.year = date.getFullYear();
      this.month = date.getMonth();
    });
  }

  private monthKey(): string {
    return `${this.year}-${(this.month + 1).toString().padStart(2, '0')}`;
  }

  private day(index: number, calendarMonth: string): number {
    const first = fromKey(calendarMonth + '-01');
    const offset = (first.getDay() + 6) % 7;
    const day = index - offset + 1;
    const count = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
    return day > 0 && day <= count ? day : 0;
  }

  private dateKey(index: number, calendarMonth: string): string {
    return `${calendarMonth}-${this.day(index, calendarMonth).toString().padStart(2, '0')}`;
  }

  private disabled(index: number, calendarMonth: string): boolean {
    return this.day(index, calendarMonth) === 0 || (this.minDate.length > 0 && this.dateKey(index, calendarMonth) < this.minDate);
  }

  private selectDate(index: number, calendarMonth: string): void {
    if (this.disabled(index, calendarMonth)) return;
    this.getUIContext().animateTo(Motion.quick(), () => this.onSelect(this.dateKey(index, calendarMonth)));
  }

  @Builder
  private dateCell(index: number, calendarMonth: string) {
    if (this.day(index, calendarMonth) > 0) {
      Button({ type: ButtonType.Normal }) {
        Stack({ alignContent: Alignment.Bottom }) {
          Text(this.day(index, calendarMonth).toString()).fontSize(14)
            .fontWeight(this.dateKey(index, calendarMonth) === this.value || this.dateKey(index, calendarMonth) === todayKey() ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.dateKey(index, calendarMonth) === this.value || this.dateKey(index, calendarMonth) === todayKey() ? this.palette.accent : this.palette.text)
            .width('100%').height(44).textAlign(TextAlign.Center)
          if (this.marks.includes(this.dateKey(index, calendarMonth))) {
            Row().width(5).height(3).borderRadius(1.5).backgroundColor(this.palette.accent).margin({ bottom: 4 })
          }
        }
      }
      .layoutWeight(1).height(44).padding(0).borderRadius(10)
      .backgroundColor(this.dateKey(index, calendarMonth) === this.value ? Materials.inset(this.palette, true) : Color.Transparent)
      .opacity(this.disabled(index, calendarMonth) ? 0.3 : 1).enabled(!this.disabled(index, calendarMonth))
      .accessibilityText(this.dateKey(index, calendarMonth)).onClick(() => this.selectDate(index, calendarMonth))
    } else {
      Blank().layoutWeight(1).height(44)
    }
  }

  build() {
    Column({ space: 4 }) {
      Row() {
        IconButton({ icon: 'left', palette: this.palette, label: '上个月', onTap: () => this.moveMonth(-1) })
        Text(`${this.year} 年 ${this.month + 1} 月`).layoutWeight(1).fontSize(15)
          .fontWeight(FontWeight.Bold).fontColor(this.palette.text).textAlign(TextAlign.Center)
        IconButton({ icon: 'right', palette: this.palette, label: '下个月', onTap: () => this.moveMonth(1) })
      }.width('100%')
      Row() {
        ForEach(this.week, (day: string) => {
          Text(day).layoutWeight(1).height(26).fontSize(12)
            .fontColor(this.palette.textFaint).textAlign(TextAlign.Center)
        }, (day: string) => day)
      }.width('100%')
      // 月键同时固定离场网格的日期，动画期间也不会读到下一个月。
      ForEach([this.monthKey()], (calendarMonth: string) => {
        Column({ space: 2 }) {
          ForEach(this.rows, (row: number) => {
            Row({ space: 2 }) {
              ForEach(this.columns, (column: number) => {
                this.dateCell(row * 7 + column, calendarMonth)
              }, (column: number) => column.toString())
            }.width('100%')
          }, (row: number) => row.toString())
        }.width('100%').transition(Motion.reveal())
      }, (calendarMonth: string) => calendarMonth)
    }.width('100%').padding(8).borderRadius(16)
      .backgroundColor(Materials.inset(this.palette))
  }
}