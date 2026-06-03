#include "reaper_plugin.h"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <deque>
#include <sstream>
#include <string>

namespace
{
constexpr const char* kExtSection = "TK_WORKBENCH_ACTION_CAPTURE";
constexpr int kMaxEvents = 32;

using SetExtStateFn = void (*)(const char*, const char*, const char*, bool);
using TimePreciseFn = double (*)();

SetExtStateFn g_setExtState = nullptr;
TimePreciseFn g_timePrecise = nullptr;
reaper_plugin_info_t* g_rec = nullptr;
int g_sequence = 0;

struct Event
{
  int sequence = 0;
  double time = 0.0;
  int section = 0;
  int command = 0;
  std::string source;
};

std::deque<Event> g_events;
int g_lastCommand = 0;
int g_lastSection = 0;
double g_lastTime = 0.0;

double now()
{
  return g_timePrecise ? g_timePrecise() : 0.0;
}

void setExt(const char* key, const std::string& value)
{
  if (g_setExtState) g_setExtState(kExtSection, key, value.c_str(), false);
}

void setExt(const char* key, const char* value)
{
  if (g_setExtState) g_setExtState(kExtSection, key, value, false);
}

std::string toString(int value)
{
  char buffer[32];
  std::snprintf(buffer, sizeof(buffer), "%d", value);
  return buffer;
}

std::string toString(double value)
{
  char buffer[64];
  std::snprintf(buffer, sizeof(buffer), "%.6f", value);
  return buffer;
}

bool shouldIgnore(int command)
{
  return command <= 0;
}

bool isDuplicate(int section, int command, double eventTime)
{
  if (section != g_lastSection || command != g_lastCommand) return false;
  return eventTime > 0.0 && g_lastTime > 0.0 && (eventTime - g_lastTime) < 0.010;
}

std::string serializeEvents()
{
  std::ostringstream output;
  for (const auto& event : g_events)
  {
    output << event.sequence << '|'
           << toString(event.time) << '|'
           << event.section << '|'
           << event.command << '|'
           << event.source << '\n';
  }
  return output.str();
}

void publishQueue()
{
  setExt("seq", toString(g_sequence));
  setExt("events", serializeEvents());
  setExt("heartbeat", toString(now()));
}

void captureAction(int section, int command, const char* source)
{
  if (shouldIgnore(command)) return;
  const double eventTime = now();
  if (isDuplicate(section, command, eventTime)) return;

  g_lastSection = section;
  g_lastCommand = command;
  g_lastTime = eventTime;

  Event event;
  event.sequence = ++g_sequence;
  event.time = eventTime;
  event.section = section;
  event.command = command;
  event.source = source ? source : "unknown";
  g_events.push_back(event);
  while (static_cast<int>(g_events.size()) > kMaxEvents) g_events.pop_front();
  publishQueue();
}

void postCommand(int command, int flag)
{
  captureAction(0, command, flag == 0 ? "postcommand" : "postcommand_flag");
}

void postCommand2(KbdSectionInfo* section, int command, int, int, int, HWND, ReaProject*)
{
  captureAction(section ? section->uniqueID : 0, command, "postcommand2");
}

bool importApi(reaper_plugin_info_t* rec)
{
  g_setExtState = reinterpret_cast<SetExtStateFn>(rec->GetFunc("SetExtState"));
  g_timePrecise = reinterpret_cast<TimePreciseFn>(rec->GetFunc("time_precise"));
  return g_setExtState != nullptr;
}

bool registerHooks(reaper_plugin_info_t* rec)
{
  if (!rec->Register("hookpostcommand2", reinterpret_cast<void*>(postCommand2))) return false;
  if (!rec->Register("hookpostcommand", reinterpret_cast<void*>(postCommand)))
  {
    rec->Register("-hookpostcommand2", reinterpret_cast<void*>(postCommand2));
    return false;
  }
  return true;
}

void unregisterHooks()
{
  if (!g_rec) return;
  g_rec->Register("-hookpostcommand", reinterpret_cast<void*>(postCommand));
  g_rec->Register("-hookpostcommand2", reinterpret_cast<void*>(postCommand2));
}

void publishUnavailable()
{
  setExt("available", "false");
  setExt("heartbeat", "");
}

void publishAvailable()
{
  setExt("available", "true");
  setExt("seq", toString(g_sequence));
  setExt("events", "");
  setExt("heartbeat", toString(now()));
}
}

extern "C"
{
REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(REAPER_PLUGIN_HINSTANCE, reaper_plugin_info_t* rec)
{
  if (!rec)
  {
    unregisterHooks();
    publishUnavailable();
    g_rec = nullptr;
    return 0;
  }

  if (rec->caller_version != REAPER_PLUGIN_VERSION || !rec->GetFunc || !rec->Register) return 0;
  if (!importApi(rec)) return 0;

  g_rec = rec;
  if (!registerHooks(rec))
  {
    publishUnavailable();
    g_rec = nullptr;
    return 0;
  }

  publishAvailable();
  return 1;
}
}