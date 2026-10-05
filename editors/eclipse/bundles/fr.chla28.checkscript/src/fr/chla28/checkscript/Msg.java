package fr.chla28.checkscript;

import java.util.Locale;

/** Textes de l'interface : anglais par défaut, français si la langue du système l'est. */
final class Msg {

	private static final boolean FRENCH = Locale.getDefault().getLanguage().equals("fr");

	private Msg() {
	}

	static String t(String fr, String en) {
		return FRENCH ? fr : en;
	}
}
