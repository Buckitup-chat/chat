defmodule Chat.Repo.Migrations.AddRightCandidatesToElectricPublication do
  use Ecto.Migration

  @tables ~w(review_post_right_candidate review_revoke_right_candidate)

  def up do
    for table <- @tables do
      execute """
      DO $$
      BEGIN
        ALTER PUBLICATION electric_publication_default ADD TABLE #{table};
      EXCEPTION
        WHEN duplicate_object THEN NULL;
      END $$;
      """
    end
  end

  def down do
    for table <- @tables do
      execute """
      DO $$
      BEGIN
        ALTER PUBLICATION electric_publication_default DROP TABLE #{table};
      EXCEPTION
        WHEN undefined_object THEN NULL;
      END $$;
      """
    end
  end
end
