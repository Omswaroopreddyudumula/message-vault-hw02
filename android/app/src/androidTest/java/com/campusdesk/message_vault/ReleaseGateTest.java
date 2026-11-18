package com.campusdesk.message_vault;

import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.*;
import org.junit.*;
import org.junit.runner.RunWith;
import java.io.File;
import static org.junit.Assert.*;

/** Drives the installed release APK through Android accessibility, without a Dart test entrypoint. */
@RunWith(AndroidJUnit4.class)
public class ReleaseGateTest {
 UiDevice d; Context c; Bundle args;
 @Before public void setup() throws Exception {
  Configurator.getInstance().setWaitForIdleTimeout(500).setWaitForSelectorTimeout(1000);
  d=UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
  c=InstrumentationRegistry.getInstrumentation().getTargetContext();
  args=InstrumentationRegistry.getArguments();
  Intent launch=c.getPackageManager().getLaunchIntentForPackage(c.getPackageName());
  launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK); c.startActivity(launch);
 }
 UiObject2 id(String name) { UiObject2 o=d.wait(Until.findObject(By.res(name)),20000); assertNotNull("Missing "+name,o);return o; }
 void click(String name) { id(name).click(); d.waitForIdle(); }
 void text(String name,String value)throws Exception { UiObject2 o=id(name);if(!"android.widget.EditText".equals(o.getClassName())){o=o.findObject(By.clazz("android.widget.EditText"));}assertNotNull("Editable "+name,o);o.click();Thread.sleep(400);o.setText(value);Thread.sleep(300);if(d.hasObject(By.pkg("com.google.android.inputmethod.latin"))||d.hasObject(By.pkg("com.android.inputmethod.latin")))d.pressBack();d.waitForIdle(); }
 boolean visible(String value){return d.hasObject(By.textContains(value))||d.hasObject(By.descContains(value));}
 void sees(String value)throws Exception{long until=System.currentTimeMillis()+30000;while(!visible(value)&&System.currentTimeMillis()<until)Thread.sleep(200);assertTrue("Missing text: "+value,visible(value));}
 @After public void diagnostic()throws Exception{shot("last-state");d.dumpWindowHierarchy(new File(c.getExternalFilesDir(null),"hierarchy.xml"));}
 void shot(String name)throws Exception {File dir=new File(c.getExternalFilesDir(null),"screenshots");dir.mkdirs();assertTrue(d.takeScreenshot(new File(dir,name+".png")));}
 void login(String who)throws Exception{text("email",args.getString(who+"Email"));text("password",args.getString("password"));click("auth_submit");id("post_input");}
 void register(String who,String first)throws Exception{if(!d.hasObject(By.res("first_name")))click("auth_toggle");text("first_name",first);text("last_name","VaultTest");text("email",args.getString(who+"Email"));text("password",args.getString("password"));click("auth_submit");id("post_input");}
 void post(String value)throws Exception{text("post_input",value);click("post_submit");sees("Message posted.");sees(value);}
 void probe(String name,String screenshot)throws Exception{click("rules_checks");click(name);sees("permission-denied");shot(screenshot);}
 @Test public void splashOnly()throws Exception {
  File dir=new File(c.getExternalFilesDir(null),"screenshots");dir.mkdirs();boolean found=false;
  for(int i=0;i<45;i++) {
   boolean flutterSplash=d.hasObject(By.res("splash"));
   android.graphics.Bitmap bitmap=InstrumentationRegistry.getInstrumentation().getUiAutomation().takeScreenshot();
   if(bitmap!=null) {
    int pixel=bitmap.getPixel(bitmap.getWidth()/8,bitmap.getHeight()/2);
    if(flutterSplash && android.graphics.Color.green(pixel)>android.graphics.Color.red(pixel)+25 && android.graphics.Color.red(pixel)<100) {
     try(java.io.FileOutputStream stream=new java.io.FileOutputStream(new File(dir,"00-splash.png"))){assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,stream));}
     found=true;bitmap.recycle();break;
    }
    bitmap.recycle();
   }
   Thread.sleep(100);
  }
  assertTrue("Styled teal splash was not visually observed",found);
 }
 @Test public void releaseFlow() throws Exception {
  id("auth_submit");click("auth_submit");sees("Enter a valid email.");shot("01-validation");
  register("b","Riley");if(d.hasObject(By.res("empty_board")))shot("02a-empty-board");click("profile");sees("student");shot("02-five-field-profile");d.pressBack();
  post("B witness retained "+args.getString("run"));shot("03-create-B");click("sign_out");
  // The screen keeps credentials in the same route only until auth routing disposes it.
  register("a","Om");text("post_input","A original "+args.getString("run"));UiObject2 submit=id("post_submit");submit.click();submit.click();sees("A original "+args.getString("run"));sees("2 messages");shot("04-create-A");
  click("rules_checks");click("repeat_post");sees("Already saved; no duplicate created.");sees("2 messages");shot("05-idempotent-retry");
  UiObject2 edit=d.findObject(By.res(java.util.regex.Pattern.compile("edit_.*")));assertNotNull(edit);edit.click();text("edit_input","A edited "+args.getString("run"));click("save_edit");sees("A edited "+args.getString("run"));shot("06-edit");
  probe("probe_foreign_edit","07-wrong-user-edit-denied");probe("probe_foreign_delete","08-wrong-user-delete-denied");probe("probe_forged","09-forged-author-denied");
  UiObject2 del=d.findObject(By.res(java.util.regex.Pattern.compile("delete_.*")));assertNotNull(del);del.click();click("confirm_delete");sees("Message deleted.");sees("B witness retained "+args.getString("run"));shot("10-delete-single");
  post("A survivor "+args.getString("run"));
  click("sign_out");click("signed_out_probe");sees("permission-denied");shot("11-signed-out-read-denied");
  text("email",args.getString("aEmail"));text("password","wrong-password-123");click("auth_submit");sees("Email or password is incorrect.");shot("12-invalid-login");
  login("a");shot("13-login-board");text("post_input","Unsent volatile draft "+args.getString("run"));shot("14-unsent-draft");
 }
 @Test public void restoredSession()throws Exception {id("post_input");sees("A survivor "+args.getString("run"));assertFalse("Draft unexpectedly persisted",d.hasObject(By.textContains("Unsent volatile draft")));shot(args.getString("label","15-restored"));}
 @Test public void afterClearData()throws Exception{id("auth_submit");shot("17-cleared-data-signed-out");login("a");sees("A survivor "+args.getString("run"));shot("18-cloud-survives-clear-data");}
 @Test public void liveWindow()throws Exception{id("post_input");sees("B live "+args.getString("run"));shot("19-live-second-window");}
 @Test public void offlineFull()throws Exception {
  id("post_input");sees("A survivor "+args.getString("run"));
  try {
   d.executeShellCommand("svc wifi disable");d.executeShellCommand("svc data disable");Thread.sleep(4000);
   String network=d.executeShellCommand("dumpsys connectivity");
   java.nio.file.Files.write(new File(c.getExternalFilesDir(null),"offline-network.txt").toPath(),network.getBytes(java.nio.charset.StandardCharsets.UTF_8));
   assertTrue("Device still has a default network",network.contains("Active default network: none"));
   text("post_input","Offline retry "+args.getString("run"));click("post_submit");
   long until=System.currentTimeMillis()+90000;while(!visible("same post ID is retained")&&System.currentTimeMillis()<until)Thread.sleep(300);
   assertTrue("Offline transaction must fail safely",visible("same post ID is retained"));shot("20-offline-post-error");
  } finally {d.executeShellCommand("svc wifi enable");d.executeShellCommand("svc data enable");}
  Thread.sleep(5000);click("post_submit");sees("Message posted.");sees("Offline retry "+args.getString("run"));shot("21-offline-retry-recovered");
 }
 @Test public void emulatorOnly()throws Exception{id("auth_submit");login("a");sees("B emulated seed");post("A emulated client "+args.getString("run"));shot("23-emulator-app");}
 @Test public void emptyBoard()throws Exception {
  id("post_input");
  while(d.hasObject(By.res(java.util.regex.Pattern.compile("delete_.*")))){d.findObject(By.res(java.util.regex.Pattern.compile("delete_.*"))).click();click("confirm_delete");sees("Message deleted.");Thread.sleep(500);}
  click("sign_out");login("b");
  while(d.hasObject(By.res(java.util.regex.Pattern.compile("delete_.*")))){d.findObject(By.res(java.util.regex.Pattern.compile("delete_.*"))).click();click("confirm_delete");sees("Message deleted.");Thread.sleep(500);}
  id("empty_board");sees("No messages yet");shot("22-empty-board");
 }
}
