import Foundation
import UIKit

struct ClaudeService {

    private static let apiURL = "https://api.anthropic.com/v1/messages"
    private static let model  = "claude-sonnet-4-6"

    // MARK: - System prompt
    // Tuned for dyscalculia — never solves, always explains in plain language
    private static let systemPrompt = """
    You are Numara, a math and number assistant for people with dyscalculia. \
    Your job is to make numbers and equations feel less scary — never to solve problems for the user.

    Rules:
    1. If you see a price or money amount: state the number plainly, then give one real-world anchor \
       (e.g. "that's about the cost of three coffees"). Keep it to 2 sentences max.
    2. If you see an equation: read it aloud naturally (e.g. "three x squared plus two x minus five equals zero"), \
       then explain what each part of the equation means in plain English. \
       Do NOT solve it. Do NOT give the answer. Just explain the parts.
    3. If you see a receipt: summarize the total and biggest line item only. One sentence each.
    4. Never use math jargon without immediately explaining it in simple words.
    5. Always speak directly to the user — use "you" not "the student".
    6. Keep every response under 60 words. Short and clear wins.
    """

    // MARK: - Main call
    static func analyze(image: UIImage, apiKey: String) async throws -> String {
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            throw NumaraError.imageEncodingFailed
        }
        let base64 = jpeg.base64EncodedString()

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64
                            ]
                        ],
                        [
                            "type": "text",
                            "text": "What do you see? Respond following your rules."
                        ]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? "unknown"
            throw NumaraError.apiError(raw)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let first = content.first,
            let text = first["text"] as? String
        else {
            throw NumaraError.parseError
        }

        return text
    }

    // MARK: - Follow-up (voice) — sends prior context + new voice question
    static func followUp(
        image: UIImage,
        priorResponse: String,
        question: String,
        apiKey: String
    ) async throws -> String {
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            throw NumaraError.imageEncodingFailed
        }
        let base64 = jpeg.base64EncodedString()

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64
                            ]
                        ],
                        [
                            "type": "text",
                            "text": "What do you see? Respond following your rules."
                        ]
                    ]
                ],
                [
                    "role": "assistant",
                    "content": priorResponse
                ],
                [
                    "role": "user",
                    "content": question
                ]
            ]
        ]

        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? "unknown"
            throw NumaraError.apiError(raw)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let first = content.first,
            let text = first["text"] as? String
        else {
            throw NumaraError.parseError
        }

        return text
    }
    // MARK: - Voice calculator system prompts
    // General mode — addition/subtraction, always anchors, never just a number
    private static let calcGeneralPrompt = """
    You are Numara, a math assistant for people with dyscalculia. \
    The user has spoken a math question out loud. Your job is to answer it in a way their brain can hold onto.

    Rules:
    1. State the answer as a plain number first.
    2. Immediately follow with one real-world anchor — something they can visualize. \
       Examples: "that's like a dozen eggs with one left over", "about the cost of a Starbucks drink", \
       "roughly the length of a school hallway in steps".
    3. Keep the whole response under 20 words.
    4. End with: "Is there anything else I can help you with?"
    5. Never explain your reasoning. Just answer + anchor + offer.
    """

    // Calculator mode — multiplication/division, triggered by "calculate" or "solve"
    // These operations are genuinely hard to anchor so we give the real answer clearly
    private static let calcSolvePrompt = """
    You are Numara, a math assistant for people with dyscalculia. \
    The user has asked you to calculate or solve something. Give them the exact answer.

    Rules:
    1. State the answer clearly and simply — just the number, no jargon.
    2. If the result is a decimal or fraction, round to one decimal place and explain what that means \
       (e.g. "2.5 — that's two and a half").
    3. Add one short anchor if it helps (optional — only if it genuinely clarifies).
    4. Keep the whole response under 25 words.
    5. End with: "Is there anything else I can help you with?"
    """

    // MARK: - Voice calculator call (no image)
    static func voiceCalculate(
        question: String,
        isSolveMode: Bool,
        apiKey: String
    ) async throws -> (answer: String, equation: String) {
        let prompt = isSolveMode ? calcSolvePrompt : calcGeneralPrompt

        // Ask Claude to also return a structured equation for the screen display
        let userMessage = """
        The user said: "\(question)"

        Respond with two lines exactly:
        EQUATION: [the equation in clean numeric form, e.g. "15 + 8 = 23" or "6 × 7 = 42"]
        ANSWER: [your spoken response following your rules]

        Nothing else. No extra lines.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 128,
            "system": prompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? "unknown"
            throw NumaraError.apiError(raw)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let first = content.first,
            let text = first["text"] as? String
        else {
            throw NumaraError.parseError
        }

        // Parse EQUATION: and ANSWER: lines
        var equation = question  // fallback to raw question
        var answer = text        // fallback to full response

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("EQUATION:") {
                equation = line.replacingOccurrences(of: "EQUATION:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("ANSWER:") {
                answer = line.replacingOccurrences(of: "ANSWER:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        return (answer: answer, equation: equation)
    }
}

// MARK: - Errors
enum NumaraError: LocalizedError {
    case imageEncodingFailed
    case apiError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: return "Could not prepare the image."
        case .apiError(let msg):   return "API error: \(msg)"
        case .parseError:          return "Could not read the response."
        }
    }
}
