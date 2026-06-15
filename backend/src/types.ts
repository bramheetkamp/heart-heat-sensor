export type WarningType = 'OVERHEATING' | 'GETTING_SICK' | 'FATIGUE_RECOVERY';

export interface User {
  id: string;
  email: string;
  password_hash: string | null;
  apple_sub: string | null;
  created_at: number;
}

export interface Reading {
  id: string;
  user_id: string;
  device_id: string;
  timestamp: number;       // Unix ms
  heart_rate: number | null;
  rr_intervals: number[];  // in ms
  temp_site1: number | null;   // Celsius (core)
  temp_site2: number | null;   // Celsius (skin)
  eda: number | null;          // skin conductance, microsiemens (µS)
  activity: string | null;     // 'rest' | 'active' | 'sleep'
  created_at: number;
}

export interface Warning {
  id: string;
  user_id: string;
  type: WarningType;
  fired_at: number;
  resolved_at: number | null;
  title: string;
  message: string;
  data: WarningData;
  created_at: number;
}

export interface WarningData {
  triggerValues: Record<string, number>;
  baselineValues: Record<string, number>;
  trend: number[];
}
