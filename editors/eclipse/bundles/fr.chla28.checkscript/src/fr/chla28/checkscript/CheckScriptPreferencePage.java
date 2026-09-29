package fr.chla28.checkscript;

import org.eclipse.jface.preference.BooleanFieldEditor;
import org.eclipse.jface.preference.ComboFieldEditor;
import org.eclipse.jface.preference.FieldEditorPreferencePage;
import org.eclipse.jface.preference.IntegerFieldEditor;
import org.eclipse.jface.preference.StringFieldEditor;
import org.eclipse.ui.IWorkbench;
import org.eclipse.ui.IWorkbenchPreferencePage;

/** Fenêtre → Préférences → CheckScript. */
public class CheckScriptPreferencePage extends FieldEditorPreferencePage implements IWorkbenchPreferencePage {

	public CheckScriptPreferencePage() {
		super(GRID);
		setPreferenceStore(Activator.getDefault().getPreferenceStore());
		setDescription("Analyse des scripts shell et Python par « check-script lsp ».\n"
				+ "Les changements s'appliquent aux éditeurs ouverts ensuite.");
	}

	@Override
	protected void createFieldEditors() {
		addField(new StringFieldEditor(Prefs.PATH, "Exécutable check-script :", getFieldEditorParent()));
		addField(new ComboFieldEditor(Prefs.LANG, "Langue :",
				new String[][] { { "Environnement", "" }, { "Français", "fr" }, { "English", "en" } },
				getFieldEditorParent()));
		addField(new ComboFieldEditor(Prefs.PROFILE, "Profil :",
				new String[][] { { "Celui du projet (.checkscript.yaml)", "" }, { "strict", "strict" },
						{ "default", "default" }, { "legacy", "legacy" } },
				getFieldEditorParent()));
		addField(new BooleanFieldEditor(Prefs.ANALYZE_ON_TYPE, "Règles intégrées pendant la frappe",
				getFieldEditorParent()));
		IntegerFieldEditor delay = new IntegerFieldEditor(Prefs.TYPING_DELAY, "Pause de frappe (ms) :",
				getFieldEditorParent());
		delay.setValidRange(100, 10000);
		addField(delay);
	}

	@Override
	public void init(IWorkbench workbench) {
	}
}
