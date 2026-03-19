#ifndef VOICE_INPUT_CORE_H
#define VOICE_INPUT_CORE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

char *voice_input_core_version(void);
bool voice_input_core_configure_tools(const char *ffmpeg_path, const char *coli_path);
char *voice_input_core_smoke_status_json(void);
char *voice_input_core_last_error_message(void);
char *voice_input_core_start_recording(void);
bool voice_input_core_stop_recording(void);
bool voice_input_core_is_recording(void);
char *voice_input_core_transcribe_audio(const char *audio_path, const char *model, bool polish);
bool voice_input_core_start_live_transcription(void);
bool voice_input_core_stop_live_transcription(void);
char *voice_input_core_get_partial_transcript(void);
void voice_input_core_string_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
