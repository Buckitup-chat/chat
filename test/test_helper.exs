File.rm_rf!("priv/test_admin_db")
File.rm_rf!("priv/test_backup_db")
File.rm_rf!("priv/test_db")
ExUnit.start()
