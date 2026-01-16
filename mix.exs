defmodule AshAuthenticationBankid.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Swedish BankID authentication strategy for Ash Authentication"
  @source_url "https://github.com/Victorbjorklund/ash_authentication_bankid"

  def project do
    [
      app: :ash_authentication_bankid,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: @description,
      package: package(),
      source_url: @source_url,
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "guides/authentication-flows.md",
          "guides/setup.md",
          "guides/api.md"
        ],
        groups_for_extras: [
          Guides: [
            "guides/authentication-flows.md",
            "guides/setup.md",
            "guides/api.md"
          ]
        ],
        source_ref: "v#{@version}",
        formatters: ["html"],
        before_closing_head_tag: &before_closing_head_tag/1
      ]
    ]
  end

  defp before_closing_head_tag(:html) do
    """
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.0/dist/katex.min.css">
    """
  end

  defp before_closing_head_tag(_), do: ""

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:ash, "~> 3.0"},
      {:ash_authentication, "~> 4.0"},
      {:bankid, "~> 0.0.1"},
      {:spark, "~> 2.0"},
      {:plug, "~> 1.16"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:igniter, "~> 0.6 and >= 0.6.29", optional: true, only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      name: "ash_authentication_bankid",
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end
end
