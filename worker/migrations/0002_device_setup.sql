ALTER TABLE devices ADD COLUMN permissions TEXT
    CHECK (permissions IS NULL OR json_valid(permissions));
