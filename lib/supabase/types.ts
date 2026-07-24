/**
 * Hand-written types matching supabase/migrations/0001_init.sql.
 *
 * TODO(Phase 1+): once a real Supabase project exists, replace this file
 * with the generated types:
 *   npx supabase gen types typescript --project-id <id> > lib/supabase/types.ts
 * Keep the shape (Database.public.Tables.*) so lib/supabase/client.ts and
 * server.ts don't need to change.
 */

export type Channel = "email" | "slack" | "whatsapp";
export type ReminderStatus = "open" | "done" | "snoozed" | "cancelled";
export type NotificationStatus = "pending" | "sending" | "sent" | "failed" | "retrying";
export type CreatedBy = "ui" | "api" | `agent:${string}`;

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
          default_channel: Channel;
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
          default_channel: Channel;
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
          channels: Channel[];
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
          channels?: Channel[];
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
          channel: Channel;
          scheduled_for: string;
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
          channel: Channel;
          scheduled_for: string;
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
          created_at: string;
          updated_at: string;
        };
        Insert: {
          user_id: string;
          timezone?: string;
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
      slack_integrations: {
        Row: {
          user_id: string;
          team_id: string;
          team_name: string | null;
          bot_token: string;
          slack_user_id: string;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          user_id: string;
          team_id: string;
          team_name?: string | null;
          bot_token: string;
          slack_user_id: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["slack_integrations"]["Insert"]>;
        Relationships: [];
      };
    };
    Views: Record<string, never>;
    Functions: {
      claim_due_notifications: {
        Args: { p_limit?: number };
        Returns: Database["public"]["Tables"]["notifications"]["Row"][];
      };
      enqueue_due_notifications: {
        Args: Record<string, never>;
        Returns: undefined;
      };
    };
  };
}
