/*
  # Add Missing Features for File Manager

  1. New Tables
    - `recent_files` - Track recently accessed files
    - `file_activities` - Log file activities for audit trail
  
  2. New Columns
    - `files.last_accessed_at` - Track when files were last accessed
    - `files.is_deleted` - Soft delete functionality
    - `files.deleted_at` - When file was deleted
  
  3. Security
    - Enable RLS on new tables
    - Add policies for authenticated users
  
  4. Functions
    - Update recent files when accessed
    - Clean up old recent entries
*/

-- Add missing columns to files table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'files' AND column_name = 'last_accessed_at'
  ) THEN
    ALTER TABLE files ADD COLUMN last_accessed_at timestamptz DEFAULT now();
  END IF;
  
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'files' AND column_name = 'is_deleted'
  ) THEN
    ALTER TABLE files ADD COLUMN is_deleted boolean DEFAULT false;
  END IF;
  
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'files' AND column_name = 'deleted_at'
  ) THEN
    ALTER TABLE files ADD COLUMN deleted_at timestamptz;
  END IF;
END $$;

-- Create recent_files table for tracking recently accessed files
CREATE TABLE IF NOT EXISTS recent_files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  file_id uuid NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  accessed_at timestamptz DEFAULT now(),
  UNIQUE(file_id, user_id)
);

ALTER TABLE recent_files ENABLE ROW LEVEL SECURITY;

-- Create file_activities table for audit trail
CREATE TABLE IF NOT EXISTS file_activities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  file_id uuid NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  activity_type text NOT NULL CHECK (activity_type IN ('upload', 'download', 'view', 'edit', 'delete', 'share', 'star', 'unstar')),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE file_activities ENABLE ROW LEVEL SECURITY;

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_recent_files_user_id ON recent_files(user_id);
CREATE INDEX IF NOT EXISTS idx_recent_files_accessed_at ON recent_files(accessed_at DESC);
CREATE INDEX IF NOT EXISTS idx_file_activities_user_id ON file_activities(user_id);
CREATE INDEX IF NOT EXISTS idx_file_activities_created_at ON file_activities(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_files_last_accessed ON files(last_accessed_at DESC);
CREATE INDEX IF NOT EXISTS idx_files_is_deleted ON files(is_deleted);

-- RLS Policies for recent_files
CREATE POLICY "Users can manage their recent files"
  ON recent_files
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- RLS Policies for file_activities
CREATE POLICY "Users can view their file activities"
  ON file_activities
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "System can insert file activities"
  ON file_activities
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Function to update recent files
CREATE OR REPLACE FUNCTION update_recent_file(file_uuid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Insert or update recent file entry
  INSERT INTO recent_files (file_id, user_id, accessed_at)
  VALUES (file_uuid, auth.uid(), now())
  ON CONFLICT (file_id, user_id)
  DO UPDATE SET accessed_at = now();
  
  -- Update last_accessed_at on the file
  UPDATE files 
  SET last_accessed_at = now()
  WHERE id = file_uuid AND owner_id = auth.uid();
  
  -- Clean up old recent entries (keep only last 50 per user)
  DELETE FROM recent_files
  WHERE user_id = auth.uid()
  AND id NOT IN (
    SELECT id FROM recent_files
    WHERE user_id = auth.uid()
    ORDER BY accessed_at DESC
    LIMIT 50
  );
END;
$$;

-- Function to log file activity
CREATE OR REPLACE FUNCTION log_file_activity(file_uuid uuid, activity text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO file_activities (file_id, user_id, activity_type)
  VALUES (file_uuid, auth.uid(), activity);
END;
$$;