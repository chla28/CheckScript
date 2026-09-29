package fr.chla28.checkscript;

import java.net.URI;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.eclipse.jface.preference.IPreferenceStore;
import org.eclipse.lsp4e.server.ProcessStreamConnectionProvider;

/** Lance « check-script lsp » avec les options des préférences. */
public class CheckScriptConnectionProvider extends ProcessStreamConnectionProvider {

	public CheckScriptConnectionProvider() {
		IPreferenceStore s = Activator.getDefault().getPreferenceStore();
		List<String> command = new ArrayList<>();
		String path = s.getString(Prefs.PATH);
		command.add(path.isBlank() ? "check-script" : path.trim());
		command.add("lsp");
		String lang = s.getString(Prefs.LANG);
		if (!lang.isBlank()) {
			command.add("--lang");
			command.add(lang);
		}
		setCommands(command);
		setWorkingDirectory(System.getProperty("user.home"));
	}

	@Override
	public Object getInitializationOptions(URI rootUri) {
		IPreferenceStore s = Activator.getDefault().getPreferenceStore();
		Map<String, Object> o = new HashMap<>();
		if (!s.getString(Prefs.LANG).isBlank()) {
			o.put("lang", s.getString(Prefs.LANG));
		}
		if (!s.getString(Prefs.PROFILE).isBlank()) {
			o.put("profile", s.getString(Prefs.PROFILE));
		}
		o.put("analyzeOnType", s.getBoolean(Prefs.ANALYZE_ON_TYPE));
		o.put("typingDelay", s.getInt(Prefs.TYPING_DELAY));
		return o;
	}

	@Override
	public String toString() {
		return "CheckScript: " + super.toString();
	}
}
