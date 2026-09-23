defmodule Chat.Repo.Migrations.AddScopeComparisonFunctions do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION scope_narrower_or_eq(a TEXT, b TEXT) RETURNS BOOLEAN AS $$
    DECLARE
      segs_a TEXT[] := string_to_array(a, '.');
      segs_b TEXT[] := string_to_array(b, '.');
    BEGIN
      IF array_length(segs_a, 1) < array_length(segs_b, 1) THEN
        RETURN FALSE;
      END IF;
      FOR i IN 1..array_length(segs_b, 1) LOOP
        IF segs_b[i] != '*' AND segs_a[i] != segs_b[i] THEN
          RETURN FALSE;
        END IF;
      END LOOP;
      RETURN TRUE;
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    """

    execute """
    CREATE OR REPLACE FUNCTION scope_intersect(a TEXT, b TEXT) RETURNS TEXT AS $$
    DECLARE
      segs_a TEXT[] := string_to_array(a, '.');
      segs_b TEXT[] := string_to_array(b, '.');
      len_a  INT   := array_length(segs_a, 1);
      len_b  INT   := array_length(segs_b, 1);
      result TEXT[] := ARRAY[]::TEXT[];
      sa TEXT; sb TEXT;
    BEGIN
      FOR i IN 1..GREATEST(len_a, len_b) LOOP
        sa := CASE WHEN i <= len_a THEN segs_a[i] ELSE NULL END;
        sb := CASE WHEN i <= len_b THEN segs_b[i] ELSE NULL END;

        IF    sa IS NULL THEN result := result || sb;
        ELSIF sb IS NULL THEN result := result || sa;
        ELSIF sa = sb    THEN result := result || sa;
        ELSIF sa = '*'   THEN result := result || sb;
        ELSIF sb = '*'   THEN result := result || sa;
        ELSE  RETURN NULL;
        END IF;
      END LOOP;
      RETURN array_to_string(result, '.');
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    """
  end

  def down do
    execute "DROP FUNCTION IF EXISTS scope_intersect(TEXT, TEXT);"
    execute "DROP FUNCTION IF EXISTS scope_narrower_or_eq(TEXT, TEXT);"
  end
end
