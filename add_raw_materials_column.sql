-- Add raw_material_ids column to items table
-- Run this in Supabase SQL Editor

-- Add the column
ALTER TABLE items 
ADD COLUMN IF NOT EXISTS raw_material_ids UUID[];

-- Add comment for documentation
COMMENT ON COLUMN items.raw_material_ids IS 'Array of UUIDs referencing grn_master_items for raw material mapping';

-- Add index for better performance when querying raw materials
CREATE INDEX IF NOT EXISTS idx_item_raw_materials 
ON items USING GIN (raw_material_ids);

-- Verify the column was added
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'items' 
AND column_name = 'raw_material_ids';