// Generic, domain-agnostic schema types shared by the functional and gut
// check-ins. `key` is a plain string so any domain can define its own dims.
export interface SliderSpec { key: string; label: string; lowLabel: string; highLabel: string; words?: readonly [string, string, string, string, string] }
export interface PillOption { key: string; label: string }
export interface DimAnswers {
  sliders: Record<string, number | null>
  pills: Record<string, string[]>
  specials: Record<string, number | string | null>
}
export interface WearableContext { activityDetected: boolean; measuredStressHigh: boolean; sleptEnough: boolean }
// `after` = the section key (slider key, or a sleep special: 'latency' | 'wakeCount')
// this pill module renders directly below — so precision pills appear inline,
// right under the section that triggered them, not all at the card bottom.
// `single` = one active pill at a time (scale-like lists, e.g. wake_recovery).
// `allowOther` = open-ended list: renders a "＋ Other" pill that lets the patient
// add their OWN option, persisted per patient (nb_checkin_custom_pills, own-rows
// RLS — never shared between users).
export interface PillModule { key: string; title?: string; after: string; when: (a: DimAnswers, w?: WearableContext) => boolean; options: PillOption[]; single?: boolean; allowOther?: boolean }
export interface DimensionSpec {
  key: string
  title: string
  accent: string
  sliders: SliderSpec[]
  hasSleepInputs?: boolean
  pills: PillModule[]
}
