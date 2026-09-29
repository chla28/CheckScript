package fr.chla28.checkscript;

import org.eclipse.core.runtime.preferences.AbstractPreferenceInitializer;
import org.eclipse.jface.preference.IPreferenceStore;

public class PreferenceInitializer extends AbstractPreferenceInitializer {
	@Override
	public void initializeDefaultPreferences() {
		IPreferenceStore s = Activator.getDefault().getPreferenceStore();
		s.setDefault(Prefs.PATH, "check-script");
		s.setDefault(Prefs.LANG, "");
		s.setDefault(Prefs.PROFILE, "");
		s.setDefault(Prefs.ANALYZE_ON_TYPE, true);
		s.setDefault(Prefs.TYPING_DELAY, 600);
	}
}
