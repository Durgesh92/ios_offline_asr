/* This header contains the C API for DurgeshAI speech recognition system */

#ifndef _DURGESH_AI_H_
#define _DURGESH_AI_H_

#ifdef __cplusplus
extern "C" {
#endif

/** Model stores all the data required for recognition
 *  it contains static data and can be shared across processing
 *  threads. */
typedef struct DurgeshAIModel DurgeshAIModel;


/** Speaker model is the same as model but contains the data
 *  for speaker identification. */
typedef struct DurgeshAISpkModel DurgeshAISpkModel;


/** Recognizer object is the main object which processes data.
 *  Each recognizer usually runs in own thread and takes audio as input.
 *  Once audio is processed recognizer returns JSON object as a string
 *  which represent decoded information - words, confidences, times, n-best lists,
 *  speaker information and so on */
typedef struct DurgeshAIRecognizer DurgeshAIRecognizer;


/** Loads model data from the file and returns the model object
 *
 * @param model_path: the path of the model on the filesystem
 @ @returns model object */
DurgeshAIModel *durgesh_ai_model_new(const char *model_path);


/** Releases the model memory
 *
 *  The model object is reference-counted so if some recognizer
 *  depends on this model, model might still stay alive. When
 *  last recognizer is released, model will be released too. */
void durgesh_ai_model_free(DurgeshAIModel *model);


/** Loads speaker model data from the file and returns the model object
 *
 * @param model_path: the path of the model on the filesystem
 * @returns model object */
DurgeshAISpkModel *durgesh_ai_spk_model_new(const char *model_path);


/** Releases the model memory
 *
 *  The model object is reference-counted so if some recognizer
 *  depends on this model, model might still stay alive. When
 *  last recognizer is released, model will be released too. */
void durgesh_ai_spk_model_free(DurgeshAISpkModel *model);

/** Creates the recognizer object
 *
 *  The recognizers process the speech and return text using shared model data
 *  @param sample_rate The sample rate of the audio you going to feed into the recognizer
 *  @returns recognizer object */
DurgeshAIRecognizer *durgesh_ai_recognizer_new(DurgeshAIModel *model, float sample_rate);


/** Creates the recognizer object with speaker recognition
 *
 *  With the speaker recognition mode the recognizer not just recognize
 *  text but also return speaker vectors one can use for speaker identification
 *
 *  @param spk_model speaker model for speaker identification
 *  @param sample_rate The sample rate of the audio you going to feed into the recognizer
 *  @returns recognizer object */
DurgeshAIRecognizer *durgesh_ai_recognizer_new_spk(DurgeshAIModel *model, DurgeshAISpkModel *spk_model, float sample_rate);


/** Creates the recognizer object with the grammar
 *
 *  Sometimes when you want to improve recognition accuracy and when you don't need
 *  to recognize large vocabulary you can specify a list of words to recognize. This
 *  will improve recognizer speed and accuracy but might return [unk] if user said
 *  something different.
 *
 *  Only recognizers with lookahead models support this type of quick configuration.
 *  Precompiled HCLG graph models are not supported.
 *
 *  @param sample_rate The sample rate of the audio you going to feed into the recognizer
 *  @param grammar The string with the list of words to recognize, for example "one two three four five [unk]"
 *
 *  @returns recognizer object */
DurgeshAIRecognizer *durgesh_ai_recognizer_new_grm(DurgeshAIModel *model, float sample_rate, const char *grammar);


/** Accept voice data
 *
 *  accept and process new chunk of voice data
 *
 *  @param data - audio data in PCM 16-bit mono format
 *  @param length - length of the audio data
 *  @returns true if silence is occured and you can retrieve a new utterance with result method */
int durgesh_ai_recognizer_accept_waveform(DurgeshAIRecognizer *recognizer, const char *data, int length);


/** Same as above but the version with the short data for language bindings where you have
 *  audio as array of shorts */
int durgesh_ai_recognizer_accept_waveform_s(DurgeshAIRecognizer *recognizer, const short *data, int length);


/** Same as above but the version with the float data for language bindings where you have
 *  audio as array of floats */
int durgesh_ai_recognizer_accept_waveform_f(DurgeshAIRecognizer *recognizer, const float *data, int length);


/** Returns speech recognition result
 *
 * @returns the result in JSON format which contains decoded line, decoded
 *          words, times in seconds and confidences. You can parse this result
 *          with any json parser
 *
 * <pre>
 * {
 *   "result" : [{
 *       "conf" : 1.000000,
 *       "end" : 1.110000,
 *       "start" : 0.870000,
 *       "word" : "what"
 *     }, {
 *       "conf" : 1.000000,
 *       "end" : 1.530000,
 *       "start" : 1.110000,
 *       "word" : "zero"
 *     }, {
 *       "conf" : 1.000000,
 *       "end" : 1.950000,
 *       "start" : 1.530000,
 *       "word" : "zero"
 *     }, {
 *       "conf" : 1.000000,
 *       "end" : 2.340000,
 *       "start" : 1.950000,
 *       "word" : "zero"
 *     }, {
 *       "conf" : 1.000000,
 *      "end" : 2.610000,
 *       "start" : 2.340000,
 *       "word" : "one"
 *     }],
 *   "text" : "what zero zero zero one"
 *  }
 * </pre>
 */
const char *durgesh_ai_recognizer_result(DurgeshAIRecognizer *recognizer);


/** Returns partial speech recognition
 *
 * @returns partial speech recognition text which is not yet finalized.
 *          result may change as recognizer process more data.
 *
 * <pre>
 * {
 *  "partial" : "cyril one eight zero"
 * }
 * </pre>
 */
const char *durgesh_ai_recognizer_partial_result(DurgeshAIRecognizer *recognizer);


/** Returns speech recognition result. Same as result, but doesn't wait for silence
 *  You usually call it in the end of the stream to get final bits of audio. It
 *  flushes the feature pipeline, so all remaining audio chunks got processed.
 *
 *  @returns speech result in JSON format.
 */
const char *durgesh_ai_recognizer_final_result(DurgeshAIRecognizer *recognizer);


/** Releases recognizer object
 *
 *  Underlying model is also unreferenced and if needed released */
void durgesh_ai_recognizer_free(DurgeshAIRecognizer *recognizer);

/** Set log level for Kaldi messages
 *
 *  @param log_level the level
 *     0 - default value to print info and error messages but no debug
 *     less than 0 - don't print info messages
 *     greather than 0 - more verbose mode
 */
void durgesh_ai_set_log_level(int log_level);

#ifdef __cplusplus
}
#endif

#endif /* _DURGESH_AI_H_ */
