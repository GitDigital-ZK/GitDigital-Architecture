
## 🧠 Teacher Agent (Primary Brain)

The main inventory-service is the **Teacher**.

It handles:
- All business logic
- Schema definitions
- Validation rules
- When and how Students should run
- Aggregation of Student results
- Final decision-making

The Teacher pushes updates, rules, and instructions outward — not the other way around.

---

## 📚 Student Agents (Specialized Workers)

Student Agents attached to this service handle **one small job each**:

Examples:
- Student: “UpdateQuantity” — writes state changes  
- Student: “FetchItemInfo” — responds only with an item record  
- Student: “LowStockWatcher” — checks thresholds  
- Student: “SyncExternalInventory” — connects to other services  
- Student: “EventEmitter” — publishes updates to the hive bus  

They run small, fast, and replaceable.  
Teacher updates them whenever the business logic changes.

---

## 🔌 How the Hive Connects

Teacher:
- Receives requests  
- Decides which Students run  
- Validates combined output  
- Returns final response

Students:
- Only perform one assigned task  
- Report results to the Teacher  
- Never make decisions outside their scope

This keeps everything lightweight and scalable.

---

## 🔗 API (Teacher-Level)

### `GET /inventory`
Returns full inventory state.

### `POST /inventory/update`
Teacher delegates quantity updates to Students → aggregates → writes final result.

### `GET /inventory/:itemId`
Teacher pulls Student “FetchItemInfo” to grab an item record.

Additional endpoints plug into Students as needed.

---

## 🛠️ Dev Notes

Local Setup:
1. Install dependencies  
2. Run main Teacher service  
3. Run Students as small processes or background tasks

Students should live in: