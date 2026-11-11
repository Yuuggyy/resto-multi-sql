-- ============================================================
-- Passage multi-restaurants de la base AUSPICES (eqqyxvonrvhnmypbdoof)
-- A coller UNE SEULE FOIS dans Supabase > SQL Editor > Run.
-- Sans danger : Auspices continue de marcher (ses lignes reçoivent
-- le slug 'auspices'). Aucune donnée n'est supprimée.
-- ============================================================

-- 1) Table des restaurants (infos + identité visuelle)
CREATE TABLE IF NOT EXISTS public.restaurants (
  slug        TEXT PRIMARY KEY,
  nom         TEXT NOT NULL,
  sous_titre  TEXT,
  adresse     TEXT,
  telephone   TEXT,
  whatsapp    TEXT,
  horaires    TEXT,
  logo_url    TEXT,
  theme       JSONB DEFAULT '{}'::jsonb,
  ouvert      BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS lecture_publique_restaurants ON public.restaurants;
CREATE POLICY lecture_publique_restaurants ON public.restaurants FOR SELECT USING (true);

-- 2) Colonne restaurant_slug sur toutes les tables
ALTER TABLE public.categories      ADD COLUMN IF NOT EXISTS restaurant_slug TEXT DEFAULT 'auspices';
ALTER TABLE public.produits        ADD COLUMN IF NOT EXISTS restaurant_slug TEXT DEFAULT 'auspices';
ALTER TABLE public.commandes       ADD COLUMN IF NOT EXISTS restaurant_slug TEXT DEFAULT 'auspices';
ALTER TABLE public.commande_items  ADD COLUMN IF NOT EXISTS restaurant_slug TEXT DEFAULT 'auspices';
ALTER TABLE public.appels_serveur  ADD COLUMN IF NOT EXISTS restaurant_slug TEXT DEFAULT 'auspices';
ALTER TABLE public.admin_profiles  ADD COLUMN IF NOT EXISTS restaurant_slug TEXT;

UPDATE public.categories     SET restaurant_slug='auspices' WHERE restaurant_slug IS NULL;
UPDATE public.produits       SET restaurant_slug='auspices' WHERE restaurant_slug IS NULL;
UPDATE public.commandes      SET restaurant_slug='auspices' WHERE restaurant_slug IS NULL;
UPDATE public.commande_items SET restaurant_slug='auspices' WHERE restaurant_slug IS NULL;
UPDATE public.appels_serveur SET restaurant_slug='auspices' WHERE restaurant_slug IS NULL;
UPDATE public.admin_profiles SET restaurant_slug='auspices' WHERE restaurant_slug IS NULL;

-- 3) Auspices devient la première ligne de la table restaurants
INSERT INTO public.restaurants (slug, nom, sous_titre, adresse, telephone, whatsapp, horaires)
SELECT 'auspices','Auspices','Cuisine Congolaise', adresse, telephone, whatsapp, horaires
FROM public.parametres LIMIT 1
ON CONFLICT (slug) DO NOTHING;

-- 4) Index
CREATE INDEX IF NOT EXISTS idx_cat_rs  ON public.categories(restaurant_slug);
CREATE INDEX IF NOT EXISTS idx_prod_rs ON public.produits(restaurant_slug);
CREATE INDEX IF NOT EXISTS idx_cmd_rs  ON public.commandes(restaurant_slug);

-- 5) Droits : chaque admin ne voit/modifie QUE son restaurant
--    (les politiques existantes sont conservées, on AJOUTE le cloisonnement)
CREATE OR REPLACE FUNCTION public.mon_restaurant() RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT restaurant_slug FROM public.admin_profiles WHERE id = auth.uid() LIMIT 1
$$;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['categories','produits','commandes','commande_items','appels_serveur'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS cloison_admin_%1$s ON public.%1$s', t);
    EXECUTE format($p$CREATE POLICY cloison_admin_%1$s ON public.%1$s AS RESTRICTIVE FOR ALL TO authenticated
      USING (restaurant_slug = public.mon_restaurant() OR auth.role()='service_role')
      WITH CHECK (restaurant_slug = public.mon_restaurant() OR auth.role()='service_role')$p$, t);
  END LOOP;
END $$;
-- NB : les clients anonymes gardent la lecture du menu et l'insertion de commandes
--      (politiques existantes). Les admins connectés sont cloisonnés par la règle ci-dessus.

NOTIFY pgrst, 'reload schema';
