defmodule Chat.AdminRoom do
  @moduledoc "Admin Room functions"

  alias Chat.Admin.{BackupSettings, CargoSettings, MediaSettings}
  alias Chat.AdminDb
  alias Chat.Card
  alias Chat.Identity

  def created? do
    AdminDb.db()
    |> CubDB.has_key?(:pub_key)
  end

  def create do
    if created?() do
      raise "Admin room already created"
    end

    AdminDb.put(:backup_settings, %BackupSettings{})
    AdminDb.put(:cargo_settings, %CargoSettings{})
    AdminDb.put(:media_settings, %MediaSettings{})

    "Admin room"
    |> Identity.create()
    |> tap(fn room_identity ->
      AdminDb.put(:pub_key, Identity.pub_key(room_identity))
    end)
  end

  def pub_key do
    AdminDb.get(:pub_key)
  end

  def visit(%Identity{public_key: admin_pub_key} = admin) do
    admin_card = admin |> Card.from_identity()

    AdminDb.put({:new_admin, admin_pub_key}, admin_card)
  rescue
    _ -> :untracked
  end

  def admin_list do
    AdminDb.values({:new_admin, 0}, {:"new_admin\0", 0})
    |> Enum.to_list()
  end

  def store_wifi_password(
        password,
        %Identity{private_key: private, public_key: public} = _admin_room_identity
      ) do
    secret = Enigma.compute_secret(private, public)

    AdminDb.put(:wifi_password, Enigma.cipher(password, secret))
  end

  def get_wifi_password(
        %Identity{private_key: private, public_key: public} = _admin_room_identity
      ) do
    secret = Enigma.compute_secret(private, public)

    :wifi_password
    |> AdminDb.get()
    |> Enigma.decipher(secret)
  rescue
    _ -> nil
  end

  def get_backup_settings do
    backup_settings = AdminDb.get(:backup_settings)

    if backup_settings do
      backup_settings
    else
      %BackupSettings{}
    end
  end

  def store_backup_settings(%BackupSettings{} = backup_settings),
    do: AdminDb.put(:backup_settings, backup_settings)

  def get_cargo_user, do: AdminDb.get(:cargo_user)

  def store_cargo_user(user_identity), do: AdminDb.put(:cargo_user, user_identity)

  def get_cargo_settings do
    cargo_settings = AdminDb.get(:cargo_settings)

    if cargo_settings do
      %CargoSettings{}
      |> Map.merge(cargo_settings)
    else
      %CargoSettings{}
    end
  end

  def store_cargo_settings(%CargoSettings{} = cargo_settings),
    do: AdminDb.put(:cargo_settings, cargo_settings)

  def get_media_settings do
    media_settings = AdminDb.get(:media_settings)

    if media_settings do
      media_settings
    else
      %MediaSettings{}
    end
  end

  def store_media_settings(%MediaSettings{} = media_settings),
    do: AdminDb.put(:media_settings, media_settings)

  def get_privacy_policy_text do
    AdminDb.get(:privacy_policy_text) || hardcoded_privacy_policy()
  end

  defp hardcoded_privacy_policy do
    """

    <h1>Privacy Policy</h1>

    <h2>1. Introduction</h2>
    <p>BuckitUp respects your privacy. This Privacy Policy outlines our practices regarding data collection, use, and sharing.

    <h2>2. No Data Collection</h2>
    <p>BuckitUp does not collect any personal or usage data through its application.

    <h2>3. No Data Sharing</h2>
    <p>Since we do not collect any data, we do not share any personal information with third parties.

    <h2>4. No Data Usage</h2>
    <p>BuckitUp does not use any personal or usage data for any purposes.

    <h2>5. Contact Us</h2>
    <p>If you have any questions about this Privacy Policy, please contact us at <a href="mailto:buckitup.lv@gmail.com">buckitup.lv@gmail.com</a>.


    <hr>

    <h1>Terms & Conditions</h1>

    <h2>Introduction</h2>
    <p>Welcome to BuckitUp. By accessing or using our application, you agree to be bound by these Terms & Conditions. If you do not agree with any part of these terms, you must not use our application.</p>

    <h2>Usage Terms</h2>
    <h3>1. Acceptance of Terms</h3>
    By downloading, installing, and using the application, you agree to comply with these Terms & Conditions and the GNU General Public License v3.0 (GPL v3.0). The full terms of the GPL v3.0 can be viewed <a href="https://www.gnu.org/licenses/gpl-3.0.en.html" target="_blank">here</a>.

    <h3>2. User Responsibilities</h3>
    <ul>
    <li>Account Registration: All user registration processes are conducted locally on your device. We do not store or manage any user data.</li>
    <li>Data Management: Users are solely responsible for managing their data and ensuring its security.</li>
    <li>Compliance: You must use the application in compliance with all applicable laws and regulations.</li>
    </ul>

    <h3>3. License and Restrictions</h3>
    <p>You are granted a non-exclusive, non-transferable, revocable license to use the application for personal or internal business purposes, in accordance with these Terms & Conditions and the GPL v3.0. You agree not to:
    <ul>
    <li>Use the application for any illegal or unauthorized purpose.</li>
    <li>Modify, adapt, hack, or reverse engineer the application, except as permitted under the GPL v3.0.</li>
    <li>Reproduce, duplicate, copy, sell, trade, or resell the application, except as permitted under the GPL v3.0.</li>
    </ul>

    <h3>4. Intellectual Property</h3>
    <p>All intellectual property rights in the application are owned by SIA BuckitUp, subject to the rights granted under the GPL v3.0.

    <h3>5. Limitation of Liability</h3>
    <p>To the fullest extent permitted by law, SIA BuckitUp shall not be liable for any indirect, incidental, special, consequential, or punitive damages, or any loss of profits or revenues, whether incurred directly or indirectly, or any loss of data, use, goodwill, or other intangible losses resulting from:
    <ul>
    <li>Your use or inability to use the application.</li>
    <li>Any unauthorized access or use of your data.</li>
    <li>Any content obtained from the application.</li>
    </ul>

    <h3>6. Disclaimer of Warranties</h3>
    <p>The application is provided “as is” and “as available” without any warranties of any kind, either express or implied, including, but not limited to, implied warranties of merchantability, fitness for a particular purpose, or non-infringement.

    <h3>7. Indemnification</h3>
    <p>You agree to indemnify, defend, and hold harmless SIA BuckitUp, its officers, directors, employees, and agents, from and against any claims, liabilities, damages, losses, and expenses, including, without limitation, reasonable legal and accounting fees, arising out of or in any way connected with your access to or use of the application or your violation of these Terms & Conditions.

    <h3>8. Governing Law</h3>
    <p>These Terms & Conditions shall be governed by and construed in accordance with the laws of Latvia, without regard to its conflict of law principles.

    <h3>9. Changes to Terms & Conditions</h3>
    <p>We reserve the right to modify or replace these Terms & Conditions at any time. We will provide notice of any changes by updating the terms on our website. Your continued use of the application after any such changes constitutes your acceptance of the new Terms & Conditions.

    <h3>10. Contact Information</h3>
    <p>If you have any questions about these Terms & Conditions, please contact us at:
    <ul>
    <li>Email: <a href="mailto:buckitup.lv@gmail.com">"buckitup.lv@gmail.com</a></li>
    <li>Address: Brāļu Kaudzīšu iela 2, 66, Riga LV-1082, Latvia</li>
    </ul>

    <p>By using our application, you acknowledge that you have read, understood, and agree to be bound by these Terms & Conditions and the GPL v3.0
    """
  end

  def store_privacy_policy_text(text), do: AdminDb.put(:privacy_policy_text, text)
end
