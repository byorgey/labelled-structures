module Inverses where

open import Level

open import Relation.Binary

open import Function.Equality
open import Function.Inverse using (Inverse)

InverseSetoid : ∀ {f₁ f₂ t₁ t₂} ->
                Setoid f₁ t₁ -> Setoid f₂ t₂ -> Setoid _ _
InverseSetoid A B = record
  { Carrier = Inverse A B
  ; _≈_ = λ f g → ∀ {x y} → x ≈A y → Inverse.to f ⟨$⟩ x ≈B Inverse.to g ⟨$⟩ y
  ; isEquivalence = record 
    { refl = λ {f} → λ x≈y → cong (Inverse.to f) x≈y
    ; sym = λ f≈g x≈y → B.sym (f≈g (A.sym x≈y))
    ; trans = λ f≈g g≈h x≈y → B.trans (f≈g A.refl) (g≈h x≈y) 
    } 
  }
  where
  open module A = Setoid A renaming (_≈_ to _≈A_)
  open module B = Setoid B renaming (_≈_ to _≈B_)
