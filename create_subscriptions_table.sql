-- Create subscriptions table for managing store subscriptions
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    org_id uuid NOT NULL,
    store_id uuid NULL,
    plan_type character varying(50) NOT NULL,
    plan_name character varying(100) NOT NULL,
    max_stores integer NULL DEFAULT 1,
    max_users_per_store integer NULL DEFAULT 5,
    start_date date NOT NULL,
    expiry_date date NOT NULL,
    grace_period_days integer NULL DEFAULT 7,
    status character varying(30) NULL DEFAULT 'active'::character varying,
    payment_status character varying(30) NULL DEFAULT 'pending'::character varying,
    amount numeric(10, 2) NOT NULL,
    currency character varying(3) NULL DEFAULT 'INR'::character varying,
    payment_gateway character varying(50) NULL,
    transaction_id character varying(100) NULL,
    auto_renew boolean NULL DEFAULT false,
    features jsonb NULL,
    is_active boolean NULL DEFAULT true,
    created_at timestamp without time zone NULL DEFAULT now(),
    updated_at timestamp without time zone NULL DEFAULT now(),
    created_by uuid NULL,
    updated_by uuid NULL,
    CONSTRAINT subscriptions_pkey PRIMARY KEY (id),
    CONSTRAINT subscriptions_org_id_fkey FOREIGN KEY (org_id) REFERENCES organizations (id) ON DELETE CASCADE
) TABLESPACE pg_default;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_sub_status ON public.subscriptions USING btree (status) TABLESPACE pg_default;
CREATE INDEX IF NOT EXISTS idx_sub_org ON public.subscriptions USING btree (org_id) TABLESPACE pg_default;
CREATE INDEX IF NOT EXISTS idx_sub_store ON public.subscriptions USING btree (store_id) TABLESPACE pg_default;
CREATE INDEX IF NOT EXISTS idx_sub_expiry ON public.subscriptions USING btree (expiry_date) TABLESPACE pg_default;

-- Insert sample subscription data (as provided)
INSERT INTO public.subscriptions (
    id, org_id, store_id, plan_type, plan_name, max_stores, max_users_per_store,
    start_date, expiry_date, grace_period_days, status, payment_status,
    amount, currency, payment_gateway, transaction_id, auto_renew, features,
    is_active, created_at, updated_at
) VALUES (
    '8cf2ff50-de80-4931-bb14-8b78e2ebff01',
    '236b6df6-46b0-479a-900a-5e2678f93aeb',
    NULL,
    'yearly',
    'Premium Plan',
    5,
    10,
    '2025-12-14',
    '2026-12-14',
    7,
    'active',
    'paid',
    3358.00,
    'INR',
    'razorpay',
    'pay_FSC2024001',
    true,
    '{"pos": true, "reports": true, "inventory": true, "api_access": true, "multi_store": true, "advanced_analytics": true}',
    true,
    '2026-01-13 10:39:33.289109',
    '2026-01-13 10:39:33.289109'
) ON CONFLICT (id) DO NOTHING;

-- Add RLS (Row Level Security) policies if needed
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

-- Policy to allow users to see only their organization's subscriptions
CREATE POLICY "Users can view their org subscriptions" ON public.subscriptions
    FOR SELECT USING (
        org_id IN (
            SELECT organization_id 
            FROM user_profiles 
            WHERE user_id = auth.uid()
        )
    );

-- Policy to allow admins to manage subscriptions
CREATE POLICY "Admins can manage subscriptions" ON public.subscriptions
    FOR ALL USING (
        EXISTS (
            SELECT 1 
            FROM user_profiles 
            WHERE user_id = auth.uid() 
            AND role IN ('admin', 'super_admin')
        )
    );