defmodule AshAuthenticationBankid do
  @moduledoc """
  Swedish BankID authentication strategy for Ash Authentication.

  This library provides a custom authentication strategy that integrates
  Swedish BankID into Ash-based applications.

  ## Installation

  Add `ash_authentication_bankid` to your list of dependencies in `mix.exs`:

      def deps do
        [
          {:ash_authentication_bankid, "~> 0.1.0"}
        ]
      end

  ## Usage

  Configure the strategy in your user resource:

      authentication do
        strategies do
          bank_id do
            order_resource MyApp.Accounts.BankIDOrder
            personal_number_field :personal_number
            given_name_field :given_name
            surname_field :surname
          end
        end
      end

  For more information, see `AshAuthentication.BankID`.
  """

  defmacro __using__(_) do
    quote do
      import AshAuthentication.BankID.Dsl
    end
  end
end
