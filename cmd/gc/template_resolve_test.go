package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gastownhall/gascity/internal/config"
)

func TestBuildProviderCommand_AppendsDefaultArgs(t *testing.T) {
	resolved := &config.ResolvedProvider{
		Command: "claude",
		Name:    "claude",
		OptionsSchema: []config.ProviderOption{
			{
				Key: "permission_mode",
				Choices: []config.OptionChoice{
					{Value: "unrestricted", FlagArgs: []string{"--dangerously-skip-permissions"}},
				},
			},
		},
		EffectiveDefaults: map[string]string{
			"permission_mode": "unrestricted",
		},
	}
	got := buildProviderCommand(resolved, t.TempDir())
	if !strings.Contains(got, "--dangerously-skip-permissions") {
		t.Errorf("buildProviderCommand() = %q, want --dangerously-skip-permissions", got)
	}
}

func TestBuildProviderCommand_AppendsSettingsArgs(t *testing.T) {
	cityDir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(cityDir, ".gc"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(cityDir, ".gc", "settings.json"), []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}

	resolved := &config.ResolvedProvider{
		Command: "claude",
		Name:    "claude",
	}
	got := buildProviderCommand(resolved, cityDir)
	if !strings.Contains(got, "--settings") {
		t.Errorf("buildProviderCommand() = %q, want --settings flag", got)
	}
}

func TestBuildProviderCommand_NoDefaultsNoSettings(t *testing.T) {
	resolved := &config.ResolvedProvider{
		Command: "mycli",
		Name:    "mycli",
	}
	got := buildProviderCommand(resolved, t.TempDir())
	if got != "mycli" {
		t.Errorf("buildProviderCommand() = %q, want %q", got, "mycli")
	}
}

func TestBuildProviderCommand_CombinesDefaultArgsAndSettings(t *testing.T) {
	cityDir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(cityDir, ".gc"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(cityDir, ".gc", "settings.json"), []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}

	resolved := &config.ResolvedProvider{
		Command: "claude",
		Name:    "claude",
		OptionsSchema: []config.ProviderOption{
			{
				Key: "permission_mode",
				Choices: []config.OptionChoice{
					{Value: "unrestricted", FlagArgs: []string{"--dangerously-skip-permissions"}},
				},
			},
		},
		EffectiveDefaults: map[string]string{
			"permission_mode": "unrestricted",
		},
	}
	got := buildProviderCommand(resolved, cityDir)
	if !strings.Contains(got, "--dangerously-skip-permissions") {
		t.Errorf("missing --dangerously-skip-permissions in %q", got)
	}
	if !strings.Contains(got, "--settings") {
		t.Errorf("missing --settings in %q", got)
	}
	if !strings.HasPrefix(got, "claude ") {
		t.Errorf("should start with 'claude ', got %q", got)
	}
}
