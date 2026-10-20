/**
 * Hand-written types matching supabase/migrations/0001_init.sql.
 *
 * TODO(Phase 1+): once a real Supabase project exists, replace this file
 * with the generated types:
 *   npx supabase gen types typescript --project-id <id> > lib/supabase/types.ts
 * Keep the shape (Database.public.Tables.*) so lib/supabase/client.ts and
 * server.ts don't need to change.
 */

/** Delivery channels supported by the database. */
export type Channel = "email" | "whatsapp" | "apns";
export type DeliveryChannel = Channel;
export type DeviceTokenEnvironment = "sandbox" | "production";
export type DeviceTokenPlatform = "ios";
export type ReminderStatus = "open" | "done" | "snoozed" | "cancelled";
export type NotificationStatus = "pending" | "sending" | "sent" | "failed" | "retrying";
export type CreatedBy = "ui" | "api" | `agent:${string}`;

export type FocusOutcome = "finished" | "progress" | "interrupted";
export type FocusHighlight = {
  user_id: string;
  local_date: string;
  reminder_id: string | null;
  reminder_title: string;
  context_slug: "work" | "sidegig";
  created_at: string;
  updated_at: string;
};
export type FocusSession = {
  id: string;
  user_id: string;
  reminder_id: string | null;
  reminder_title: string;
  context_slug: "work" | "sidegig";
  duration_minutes: number;
  intended_outcome: string | null;
  started_at: string;
  last_resumed_at: string | null;
  paused_at: string | null;
  elapsed_seconds: number;
  finished_at: string | null;
  outcome: FocusOutcome | null;
  next_step: string | null;
  updated_at: string;
  /** Set when started from a Focus time assignment (migration 0016). */
  assignment_id?: string | null;
};
export type FocusState = {
  server_now: string;
  timezone: string;
  local_date: string;
  highlight: FocusHighlight | null;
  active_session: FocusSession | null;
};

export type FocusContextSlug = "work" | "sidegig";
export type FocusPreferences = {
  user_id: string;
  preferred_minutes: number;
  updated_at: string;
};
/** Weekly availability. `weekdays` is ISO (1=Mon .. 7=Sun); `start_time` is account-local "HH:MM:SS". */
export type FocusTime = {
  id: string;
  label: string | null;
  context_slug: FocusContextSlug;
  weekdays: number[];
  start_time: string;
  budget_minutes: number;
  enabled: boolean;
  updated_at: string;
};
export type FocusAssignmentState = "planned" | "in_progress" | "reviewed" | "skipped" | "moved" | "cancelled";
/** Row shape inside get_focus_dashboard_v2().assignments (only planned/in_progress are returned). */
export type FocusAssignment = {
  id: string;
  reminder_id: string | null;
  reminder_title: string;
  context_slug: FocusContextSlug;
  focus_time_id: string | null;
  focus_time_label: string | null;
  local_date: string;
  start_time: string;
  planned_minutes: number;
  position: number;
  state: FocusAssignmentState;
  moved_to: string | null;
  updated_at: string;
  /** Live reminder deadline for the "starts after it is due" warning. */
  due_at: string | null;
  /** Order ship-by date (YYYY-MM-DD) when the reminder is an order. */
  ship_by: string | null;
};
export type FocusDashboard = FocusState & {
  preferred_minutes: number;
  highlight_next_step: string | null;
  session_next_step: string | null;
  focus_times: FocusTime[];
  assignments: FocusAssignment[];
  /** Highest Focus migration the dashboard knows; 17 adds planned intents and restore_focus_time. */
  focus_api?: number;
};
/** Table rows (read-only for clients; writes go through RPCs). */
export type FocusTimeRow = FocusTime & { user_id: string; archived_at: string | null; created_at: string };
export type FocusAssignmentRow = Omit<FocusAssignment, "due_at" | "ship_by" | "focus_time_label"> & {
  user_id: string; created_at: string;
};

export interface Database {
  public: {
    Tables: {
      contexts: {
        Row: {
          id: string;
          user_id: string;
          name: string;
          slug: string;
          color: string;
          default_channel: DeliveryChannel;
          quiet_hours: Record<string, unknown>;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          name: string;
          slug: string;
          color: string;
          default_channel: DeliveryChannel;
          quiet_hours?: Record<string, unknown>;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["contexts"]["Insert"]>;
        Relationships: [];
      };
      reminders: {
        Row: {
          id: string;
          user_id: string;
          context_id: string;
          title: string;
          notes: string | null;
          due_at: string | null;
          recurrence: string | null;
          channels: DeliveryChannel[];
          status: ReminderStatus;
          snoozed_until: string | null;
          tags: string[];
          is_order: boolean;
          created_by: CreatedBy;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          context_id: string;
          title: string;
          notes?: string | null;
          due_at?: string | null;
          recurrence?: string | null;
          channels?: DeliveryChannel[];
          status?: ReminderStatus;
          snoozed_until?: string | null;
          tags?: string[];
          is_order?: boolean;
          created_by?: CreatedBy;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["reminders"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "reminders_context_id_fkey";
            columns: ["context_id"];
            isOneToOne: false;
            referencedRelation: "contexts";
            referencedColumns: ["id"];
          }
        ];
      };
      orders: {
        Row: {
          reminder_id: string;
          user_id: string;
          order_ref: string | null;
          recipient_name: string | null;
          ship_to: Record<string, unknown> | null;
          ship_by: string | null;
          carrier: string | null;
          tracking_number: string | null;
          shippo_transaction_id: string | null;
          shipped_at: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          reminder_id: string;
          user_id: string;
          order_ref?: string | null;
          recipient_name?: string | null;
          ship_to?: Record<string, unknown> | null;
          ship_by?: string | null;
          carrier?: string | null;
          tracking_number?: string | null;
          shippo_transaction_id?: string | null;
          shipped_at?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["orders"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "orders_reminder_id_fkey";
            columns: ["reminder_id"];
            isOneToOne: true;
            referencedRelation: "reminders";
            referencedColumns: ["id"];
          }
        ];
      };
      notifications: {
        Row: {
          id: string;
          user_id: string;
          reminder_id: string;
          channel: DeliveryChannel;
          scheduled_for: string;
          occurrence_at: string;
          superseded_at: string | null;
          delivery_started_at: string | null;
          sent_at: string | null;
          status: NotificationStatus;
          attempt_count: number;
          provider_message_id: string | null;
          error: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          reminder_id: string;
          channel: DeliveryChannel;
          scheduled_for: string;
          occurrence_at?: string;
          superseded_at?: string | null;
          delivery_started_at?: string | null;
          sent_at?: string | null;
          status?: NotificationStatus;
          attempt_count?: number;
          provider_message_id?: string | null;
          error?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["notifications"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "notifications_reminder_id_fkey";
            columns: ["reminder_id"];
            isOneToOne: false;
            referencedRelation: "reminders";
            referencedColumns: ["id"];
          }
        ];
      };
      api_keys: {
        Row: {
          id: string;
          user_id: string;
          name: string;
          key_hash: string;
          scopes: string[];
          require_delete_confirmation: boolean;
          last_used_at: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          name: string;
          key_hash: string;
          scopes?: string[];
          require_delete_confirmation?: boolean;
          last_used_at?: string | null;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["api_keys"]["Insert"]>;
        Relationships: [];
      };
      user_settings: {
        Row: {
          user_id: string;
          timezone: string;
          onboarded_at: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          user_id: string;
          timezone?: string;
          onboarded_at?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["user_settings"]["Insert"]>;
        Relationships: [];
      };
      work_details: {
        Row: {
          reminder_id: string;
          user_id: string;
          manager_name: string | null;
          department_resource: string | null;
          project_name: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          reminder_id: string;
          user_id: string;
          manager_name?: string | null;
          department_resource?: string | null;
          project_name?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["work_details"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "work_details_reminder_id_fkey";
            columns: ["reminder_id"];
            isOneToOne: true;
            referencedRelation: "reminders";
            referencedColumns: ["id"];
          }
        ];
      };
      sidegig_details: {
        Row: {
          reminder_id: string;
          user_id: string;
          initiative_name: string | null;
          client_name: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          reminder_id: string;
          user_id: string;
          initiative_name?: string | null;
          client_name?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["sidegig_details"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "sidegig_details_reminder_id_fkey";
            columns: ["reminder_id"];
            isOneToOne: true;
            referencedRelation: "reminders";
            referencedColumns: ["id"];
          }
        ];
      };
      shopping_items: {
        Row: {
          id: string;
          reminder_id: string;
          user_id: string;
          label: string;
          checked: boolean;
          position: number;
          created_at: string;
        };
        Insert: {
          id?: string;
          reminder_id: string;
          user_id: string;
          label: string;
          checked?: boolean;
          position: number;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["shopping_items"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "shopping_items_reminder_id_fkey";
            columns: ["reminder_id"];
            isOneToOne: false;
            referencedRelation: "reminders";
            referencedColumns: ["id"];
          }
        ];
      };
      focus_highlights: {
        Row: FocusHighlight;
        Insert: FocusHighlight;
        Update: Partial<FocusHighlight>;
        Relationships: [];
      };
      focus_sessions: {
        Row: FocusSession;
        Insert: FocusSession;
        Update: Partial<FocusSession>;
        Relationships: [];
      };
      focus_preferences: {
        Row: FocusPreferences;
        Insert: FocusPreferences;
        Update: Partial<FocusPreferences>;
        Relationships: [];
      };
      focus_times: {
        Row: FocusTimeRow;
        Insert: FocusTimeRow;
        Update: Partial<FocusTimeRow>;
        Relationships: [];
      };
      focus_assignments: {
        Row: FocusAssignmentRow;
        Insert: FocusAssignmentRow;
        Update: Partial<FocusAssignmentRow>;
        Relationships: [];
      };
      home_maintenance: {
        Row: { reminder_id: string; user_id: string; category: string; asset: string; repeat_months: number | null; repeat_days: number | null; details: Record<string,string> };
        Insert: { reminder_id: string; user_id: string; category: string; asset?: string; repeat_months?: number | null; repeat_days?: number | null; details?: Record<string,string> };
        Update: Partial<Database["public"]["Tables"]["home_maintenance"]["Insert"]>;
        Relationships: [];
      };
      home_service_records: {
        Row: { id: string; user_id: string; reminder_id: string | null; title: string; category: string; asset: string; serviced_at: string; notes: string; created_at: string; details: Record<string,string> };
        Insert: { user_id: string; reminder_id?: string | null; title: string; category: string; asset: string; serviced_at: string; notes?: string; details?: Record<string,string> };
        Update: Partial<Database["public"]["Tables"]["home_service_records"]["Insert"]>;
        Relationships: [];
      };
      device_tokens: {
        Row: {
          id: string;
          user_id: string;
          token: string;
          platform: DeviceTokenPlatform;
          environment: DeviceTokenEnvironment;
          app_version: string | null;
          last_seen_at: string;
          disabled_at: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          token: string;
          platform?: DeviceTokenPlatform;
          environment: DeviceTokenEnvironment;
          app_version?: string | null;
          last_seen_at?: string;
          disabled_at?: string | null;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["device_tokens"]["Insert"]>;
        Relationships: [];
      };
      local_schedules: {
        Row: {
          user_id: string;
          reminder_id: string;
          device_token_id: string;
          fire_at: string;
          scheduled_at: string;
        };
        Insert: {
          user_id: string;
          reminder_id: string;
          device_token_id: string;
          fire_at: string;
          scheduled_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["local_schedules"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "local_schedules_reminder_id_fkey";
            columns: ["reminder_id"];
            isOneToOne: false;
            referencedRelation: "reminders";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "local_schedules_device_token_id_fkey";
            columns: ["device_token_id"];
            isOneToOne: false;
            referencedRelation: "device_tokens";
            referencedColumns: ["id"];
          }
        ];
      };
    };
    Views: Record<string, never>;
    Functions: {
      get_sidegig_dashboard: { Args: Record<string, never>; Returns: import("../sidegig").GigDashboard };
      sidegig_mutate: { Args: { p_operation_id: string; p_action: string; p_id: string; p_data: import("../sidegig").GigPayload }; Returns: string };
      get_focus_state: {
        Args: Record<string, never>;
        Returns: FocusState;
      };
      set_focus_highlight: {
        Args: { p_reminder_id: string | null };
        Returns: string;
      };
      start_focus_session: {
        Args: { p_id: string; p_reminder_id: string; p_duration_minutes: number; p_intended_outcome?: string | null };
        Returns: string;
      };
      pause_focus_session: {
        Args: { p_id: string; p_expected_updated_at: string };
        Returns: string;
      };
      resume_focus_session: {
        Args: { p_id: string; p_expected_updated_at: string };
        Returns: string;
      };
      finish_focus_session: {
        Args: { p_id: string; p_expected_updated_at: string; p_outcome: FocusOutcome; p_next_step?: string | null };
        Returns: string;
      };
      get_focus_dashboard_v2: {
        Args: Record<string, never>;
        Returns: FocusDashboard;
      };
      save_focus_preferences: {
        Args: { p_preferred_minutes: number };
        Returns: number;
      };
      save_focus_time: {
        Args: {
          p_id: string; p_label: string | null; p_context_slug: FocusContextSlug; p_weekdays: number[];
          p_start_time: string; p_budget_minutes?: number; p_enabled?: boolean;
        };
        Returns: string;
      };
      archive_focus_time: {
        Args: { p_id: string };
        Returns: string;
      };
      restore_focus_time: {
        Args: { p_id: string; p_enabled?: boolean };
        Returns: string;
      };
      assign_focus_work: {
        Args: {
          p_id: string; p_reminder_id: string; p_focus_time_id: string | null; p_local_date: string;
          p_start_time: string | null; p_planned_minutes: number;
        };
        Returns: string;
      };
      skip_focus_work: {
        Args: { p_id: string };
        Returns: string;
      };
      start_assigned_focus: {
        Args: { p_session_id: string; p_assignment_id: string; p_duration_minutes?: number | null; p_intended_outcome?: string | null };
        Returns: string;
      };
      save_home_task: {
        Args: { p_id: string | null; p_title: string; p_notes: string; p_due_at: string; p_category: string; p_asset: string; p_repeat_months: number | null; p_channels: Channel[]; p_details?: Record<string,string>; p_repeat_days?: number | null };
        Returns: string;
      };
      save_home_maintenance: {
        Args: { p_id: string | null; p_title: string; p_notes: string; p_due_at: string; p_category: string; p_asset: string; p_repeat_months: number | null; p_channels: Channel[] };
        Returns: string;
      };
      record_home_service: {
        Args: { p_id: string; p_expected_updated_at: string; p_serviced_at: string; p_notes: string };
        Returns: string;
      };
      claim_due_notifications: {
        Args: { p_limit?: number };
        Returns: Database["public"]["Tables"]["notifications"]["Row"][];
      };
      enqueue_due_notifications: {
        Args: Record<string, never>;
        Returns: undefined;
      };
      retry_notification: {
        Args: { p_notification_id: string };
        Returns: string;
      };
      create_reminder: {
        Args: {
          p_title: string;
          p_notes: string | null;
          p_due_at: string | null;
          p_context_id: string;
          p_channels: DeliveryChannel[];
          p_is_order: boolean;
          p_order_ref: string | null;
          p_recipient_name: string | null;
          p_ship_by: string | null;
          p_carrier: string | null;
        };
        Returns: string;
      };
      update_reminder: {
        Args: {
          p_id: string;
          p_title: string;
          p_notes: string | null;
          p_due_at: string | null;
          p_context_id: string;
          p_channels: DeliveryChannel[];
          p_is_order: boolean;
        };
        Returns: string;
      };
      mark_shipped: {
        Args: {
          p_reminder_id: string;
          p_tracking_number: string | null;
          p_carrier: string | null;
        };
        Returns: string;
      };
      create_follow_up: {
        Args: { p_reminder_id: string };
        Returns: string;
      };
      add_shopping_item: {
        Args: { p_reminder_id: string; p_label: string };
        Returns: string;
      };
    };
  };
}
