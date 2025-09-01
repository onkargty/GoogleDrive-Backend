-- Enable RLS and secure policies for files table
ALTER TABLE files ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert their own files"
  ON files
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Users can view their own files"
  ON files
  FOR SELECT
  TO authenticated
  USING (auth.uid() = owner_id);

CREATE POLICY "Users can update their own files"
  ON files
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Users can delete their own files"
  ON files
  FOR DELETE
  TO authenticated
  USING (auth.uid() = owner_id);
