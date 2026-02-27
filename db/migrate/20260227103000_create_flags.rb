class CreateFlags < ActiveRecord::Migration[8.0]
  def change
    create_table :flags do |t|
      t.references :contract, null: false, foreign_key: true
      t.string :country_code, null: false
      t.string :flag_key, null: false
      t.string :severity, null: false
      t.decimal :confidence, precision: 4, scale: 3, null: false, default: 0.8
      t.decimal :data_completeness, precision: 4, scale: 3, null: false, default: 1.0
      t.json :evidence, null: false, default: {}
      t.string :fingerprint, null: false
      t.datetime :detected_at, null: false

      t.timestamps
    end

    add_index :flags, [ :contract_id, :flag_key ], unique: true
    add_index :flags, [ :country_code, :flag_key ]
  end
end
