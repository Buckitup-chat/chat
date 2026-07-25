defmodule Chat.Repo.Migrations.AddReviewsToElectricPublication do
  use Ecto.Migration

  @tables ~w(review review_public_passwords review_post_right review_revoke_right review_list)

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
