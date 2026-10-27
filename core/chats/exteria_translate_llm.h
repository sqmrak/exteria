#ifndef EXTERIA_TRANSLATE_LLM_H
#define EXTERIA_TRANSLATE_LLM_H

#include <stddef.h>

#include "exteria_status.h"

/* the rules of the AI translator that need no network: which model takes which request field, and the texts of the
   prompts */

#define EXTERIA_LLM_MODEL_MAX 160

/* the model takes a temperature: not the GPT-5 family, and of Gemini only the 2 family and 3.1 */
int exteria_llm_supports_temperature(const char *model);

typedef enum {
    /* the model does not reason, or is not named: the request carries nothing about reasoning */
    EXTERIA_LLM_REASONING_NONE,
    /* "reasoning_effort": effort */
    EXTERIA_LLM_REASONING_EFFORT,
    /* "thinking": {"type": "disabled"} */
    EXTERIA_LLM_REASONING_THINKING_OFF,
    /* "reasoning": {"effort": effort}, the form OpenRouter takes */
    EXTERIA_LLM_REASONING_ROUTER,
    /* the AI Gateway of Vercel: "reasoning" as above, or for DeepSeek 4 its own "thinking" option, and always the sort option */
    EXTERIA_LLM_REASONING_GATEWAY,
    EXTERIA_LLM_REASONING_GATEWAY_DEEPSEEK_OFF,
    /* "generationConfig": {"thinkingConfig": {...}} of the Vertex API */
    EXTERIA_LLM_REASONING_VERTEX
} exteria_llm_reasoning_style;

typedef struct exteria_llm_reasoning {
    exteria_llm_reasoning_style style;
    /* "none", "minimal", "low" */
    const char *effort;
    /* the Vertex form: either a token budget (Gemini 2) or a level name */
    int has_budget;
    int budget;
    const char *level;
} exteria_llm_reasoning;

/* base_url is the base address as the request uses it, with no slash at its end; it decides between the named hosts */
void exteria_llm_plan_reasoning(const char *base_url, const char *model, exteria_llm_reasoning *plan);

/* the system prompt used when the person set none */
const char *exteria_llm_default_system(void);

/* the user prompt: template with @text and @toLang filled, or the default "Translate to L: <TEXT>t</TEXT>" for an
   empty template; the marks are replaced in one pass */
exteria_status exteria_llm_user_prompt(const char *template_text, const char *text, const char *language, int custom_system, char *out, size_t cap);

/* the message that carries the context lines */
exteria_status exteria_llm_context_prompt(const char *context, char *out, size_t cap);

#endif
