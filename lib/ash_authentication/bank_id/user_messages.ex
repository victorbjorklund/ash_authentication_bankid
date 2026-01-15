defmodule AshAuthentication.BankID.UserMessages do
  @moduledoc """
  User-facing messages for BankID authentication in multiple languages.

  Provides translations for UI text and hint codes based on BankID's
  recommended user messages. Supports Swedish (`:sv`) and English (`:en`).

  ## Usage

      iex> UserMessages.hint_message("outstandingTransaction", :en)
      "Starting BankID..."

      iex> UserMessages.hint_message("userCancel", :sv)
      "Åtgärden avbröts."

      iex> UserMessages.ui_text(:title, :en)
      "Start the BankID app"
  """

  @type locale :: :en | :sv
  @type hint_code :: String.t()
  @type ui_key :: atom()

  @doc """
  Get translated message for a BankID hint code.

  ## Parameters

    * `hint_code` - The hint code from BankID API (e.g., "outstandingTransaction")
    * `locale` - Language locale (`:en` or `:sv`, defaults to `:en`)

  ## Examples

      iex> hint_message("started", :en)
      "BankID app opened. Please complete authentication."

      iex> hint_message("userCancel", :sv)
      "Åtgärden avbröts."
  """
  @spec hint_message(hint_code(), locale()) :: String.t()
  def hint_message(hint_code, locale \\ :en)

  # Pending states - English
  def hint_message("outstandingTransaction", :en),
    do: "Starting BankID..."

  def hint_message("noClient", :en),
    do: "Searching for BankID app..."

  def hint_message("started", :en),
    do: "BankID app opened. Please complete authentication."

  def hint_message("userSign", :en),
    do: "Enter your security code in the BankID app."

  def hint_message("userMrtd", :en),
    do: "Show your ID card to the camera."

  def hint_message("userCallConfirm", :en),
    do: "Press the button in BankID app."

  # Pending states - Swedish
  def hint_message("outstandingTransaction", :sv),
    do: "Startar BankID..."

  def hint_message("noClient", :sv),
    do: "Söker efter BankID-appen..."

  def hint_message("started", :sv),
    do: "BankID-appen öppnad. Slutför autentiseringen."

  def hint_message("userSign", :sv),
    do: "Ange din säkerhetskod i BankID-appen."

  def hint_message("userMrtd", :sv),
    do: "Visa ditt ID-kort för kameran."

  def hint_message("userCallConfirm", :sv),
    do: "Tryck på knappen i BankID-appen."

  # Failed states - English
  def hint_message("userCancel", :en),
    do: "Action cancelled. Please try again."

  def hint_message("cancelled", :en),
    do: "The BankID operation was cancelled."

  def hint_message("startFailed", :en),
    do: "Failed to start BankID. Is the app installed?"

  def hint_message("expiredTransaction", :en),
    do: "The request expired. Please try again."

  def hint_message("certificateErr", :en),
    do: "BankID certificate error. Please contact your bank."

  def hint_message("userDeclinedCall", :en),
    do: "Authentication was declined."

  # Failed states - Swedish
  def hint_message("userCancel", :sv),
    do: "Åtgärden avbröts."

  def hint_message("cancelled", :sv),
    do: "BankID-åtgärden avbröts."

  def hint_message("startFailed", :sv),
    do: "Kunde inte starta BankID. Är appen installerad?"

  def hint_message("expiredTransaction", :sv),
    do: "Begäran har gått ut. Försök igen."

  def hint_message("certificateErr", :sv),
    do: "BankID-certifikatfel. Kontakta din bank."

  def hint_message("userDeclinedCall", :sv),
    do: "Autentisering avvisades."

  # Default fallback
  def hint_message(_code, :en),
    do: "Please wait..."

  def hint_message(_code, :sv),
    do: "Vänta..."

  @doc """
  Get translated UI text for the BankID authentication page.

  ## Parameters

    * `key` - The UI element key (atom)
    * `locale` - Language locale (`:en` or `:sv`, defaults to `:en`)

  ## Examples

      iex> ui_text(:title, :en)
      "Start the BankID app"

      iex> ui_text(:title, :sv)
      "Starta BankID-appen"
  """
  @spec ui_text(ui_key(), locale()) :: String.t()
  def ui_text(key, locale \\ :en)

  # English UI text
  def ui_text(:title, :en), do: "Start the BankID app"
  def ui_text(:instruction_1, :en), do: "Start the BankID app and press Scan QR code."
  def ui_text(:instruction_2, :en), do: "Then scan this QR code:"
  def ui_text(:open_on_device, :en), do: "Open BankID on this device instead."
  def ui_text(:loading, :en), do: "Loading..."
  def ui_text(:success_title, :en), do: "Authentication successful!"
  def ui_text(:success_subtitle, :en), do: "Redirecting..."
  def ui_text(:error_title, :en), do: "Identification failed"
  def ui_text(:cancel, :en), do: "Cancel"
  def ui_text(:try_again, :en), do: "Try again"
  def ui_text(:time_left_minutes, :en), do: fn minutes -> "#{minutes} minute#{if minutes != 1, do: "s"} left" end
  def ui_text(:time_left_less_than_minute, :en), do: "Less than a minute left"
  def ui_text(:qr_aria_label_clickable, :en), do: "BankID authentication QR code. Click to open the BankID app on this device, or scan the code with your mobile BankID app to authenticate."
  def ui_text(:qr_aria_label, :en), do: "BankID authentication QR code. Scan this code with your mobile BankID app to begin authentication."

  # Swedish UI text
  def ui_text(:title, :sv), do: "Starta BankID-appen"
  def ui_text(:instruction_1, :sv), do: "Starta BankID-appen och tryck på Skanna QR-kod."
  def ui_text(:instruction_2, :sv), do: "Skanna sedan denna QR-kod:"
  def ui_text(:open_on_device, :sv), do: "Öppna BankID på den här enheten istället."
  def ui_text(:loading, :sv), do: "Laddar..."
  def ui_text(:success_title, :sv), do: "Autentisering lyckades!"
  def ui_text(:success_subtitle, :sv), do: "Omdirigerar..."
  def ui_text(:error_title, :sv), do: "Identifiering misslyckades"
  def ui_text(:cancel, :sv), do: "Avbryt"
  def ui_text(:try_again, :sv), do: "Försök igen"
  def ui_text(:time_left_minutes, :sv), do: fn minutes -> "#{minutes} minut#{if minutes != 1, do: "er"} kvar" end
  def ui_text(:time_left_less_than_minute, :sv), do: "Mindre än en minut kvar"
  def ui_text(:qr_aria_label_clickable, :sv), do: "BankID autentiserings QR-kod. Klicka för att öppna BankID-appen på den här enheten, eller skanna koden med din mobila BankID-app för att autentisera."
  def ui_text(:qr_aria_label, :sv), do: "BankID autentiserings QR-kod. Skanna denna kod med din mobila BankID-app för att börja autentisering."

  # Default fallback
  def ui_text(_key, _locale), do: ""

  @doc """
  Get timeout message with the number of minutes.

  ## Parameters

    * `minutes` - Number of minutes for timeout
    * `locale` - Language locale (`:en` or `:sv`, defaults to `:en`)

  ## Examples

      iex> timeout_message(5, :en)
      "Authentication timed out after 5 minutes"

      iex> timeout_message(1, :sv)
      "Autentiseringen avbröts efter 1 minut"
  """
  @spec timeout_message(integer(), locale()) :: String.t()
  def timeout_message(minutes, locale \\ :en)

  def timeout_message(minutes, :en) do
    "Authentication timed out after #{minutes} minute#{if minutes != 1, do: "s"}"
  end

  def timeout_message(minutes, :sv) do
    "Autentiseringen avbröts efter #{minutes} minut#{if minutes != 1, do: "er"}"
  end
end
