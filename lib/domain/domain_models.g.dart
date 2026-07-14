// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'domain_models.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetNodeIdentityCollection on Isar {
  IsarCollection<NodeIdentity> get nodeIdentitys => this.collection();
}

const NodeIdentitySchema = CollectionSchema(
  name: r'NodeIdentity',
  id: 9038499392437358949,
  properties: {
    r'cryptographicPublicKey': PropertySchema(
      id: 0,
      name: r'cryptographicPublicKey',
      type: IsarType.string,
    ),
    r'hasValidKeyFormat': PropertySchema(
      id: 1,
      name: r'hasValidKeyFormat',
      type: IsarType.bool,
    ),
    r'localAlias': PropertySchema(
      id: 2,
      name: r'localAlias',
      type: IsarType.string,
    ),
    r'reliabilityScore': PropertySchema(
      id: 3,
      name: r'reliabilityScore',
      type: IsarType.long,
    )
  },
  estimateSize: _nodeIdentityEstimateSize,
  serialize: _nodeIdentitySerialize,
  deserialize: _nodeIdentityDeserialize,
  deserializeProp: _nodeIdentityDeserializeProp,
  idName: r'id',
  indexes: {
    r'cryptographicPublicKey': IndexSchema(
      id: -5110183270848784316,
      name: r'cryptographicPublicKey',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'cryptographicPublicKey',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _nodeIdentityGetId,
  getLinks: _nodeIdentityGetLinks,
  attach: _nodeIdentityAttach,
  version: '3.1.0+1',
);

int _nodeIdentityEstimateSize(
  NodeIdentity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.cryptographicPublicKey.length * 3;
  bytesCount += 3 + object.localAlias.length * 3;
  return bytesCount;
}

void _nodeIdentitySerialize(
  NodeIdentity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.cryptographicPublicKey);
  writer.writeBool(offsets[1], object.hasValidKeyFormat);
  writer.writeString(offsets[2], object.localAlias);
  writer.writeLong(offsets[3], object.reliabilityScore);
}

NodeIdentity _nodeIdentityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = NodeIdentity(
    cryptographicPublicKey: reader.readString(offsets[0]),
    localAlias: reader.readString(offsets[2]),
    reliabilityScore: reader.readLongOrNull(offsets[3]) ?? 0,
  );
  object.id = id;
  return object;
}

P _nodeIdentityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readBool(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readLongOrNull(offset) ?? 0) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _nodeIdentityGetId(NodeIdentity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _nodeIdentityGetLinks(NodeIdentity object) {
  return [];
}

void _nodeIdentityAttach(
    IsarCollection<dynamic> col, Id id, NodeIdentity object) {
  object.id = id;
}

extension NodeIdentityByIndex on IsarCollection<NodeIdentity> {
  Future<NodeIdentity?> getByCryptographicPublicKey(
      String cryptographicPublicKey) {
    return getByIndex(r'cryptographicPublicKey', [cryptographicPublicKey]);
  }

  NodeIdentity? getByCryptographicPublicKeySync(String cryptographicPublicKey) {
    return getByIndexSync(r'cryptographicPublicKey', [cryptographicPublicKey]);
  }

  Future<bool> deleteByCryptographicPublicKey(String cryptographicPublicKey) {
    return deleteByIndex(r'cryptographicPublicKey', [cryptographicPublicKey]);
  }

  bool deleteByCryptographicPublicKeySync(String cryptographicPublicKey) {
    return deleteByIndexSync(
        r'cryptographicPublicKey', [cryptographicPublicKey]);
  }

  Future<List<NodeIdentity?>> getAllByCryptographicPublicKey(
      List<String> cryptographicPublicKeyValues) {
    final values = cryptographicPublicKeyValues.map((e) => [e]).toList();
    return getAllByIndex(r'cryptographicPublicKey', values);
  }

  List<NodeIdentity?> getAllByCryptographicPublicKeySync(
      List<String> cryptographicPublicKeyValues) {
    final values = cryptographicPublicKeyValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'cryptographicPublicKey', values);
  }

  Future<int> deleteAllByCryptographicPublicKey(
      List<String> cryptographicPublicKeyValues) {
    final values = cryptographicPublicKeyValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'cryptographicPublicKey', values);
  }

  int deleteAllByCryptographicPublicKeySync(
      List<String> cryptographicPublicKeyValues) {
    final values = cryptographicPublicKeyValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'cryptographicPublicKey', values);
  }

  Future<Id> putByCryptographicPublicKey(NodeIdentity object) {
    return putByIndex(r'cryptographicPublicKey', object);
  }

  Id putByCryptographicPublicKeySync(NodeIdentity object,
      {bool saveLinks = true}) {
    return putByIndexSync(r'cryptographicPublicKey', object,
        saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByCryptographicPublicKey(List<NodeIdentity> objects) {
    return putAllByIndex(r'cryptographicPublicKey', objects);
  }

  List<Id> putAllByCryptographicPublicKeySync(List<NodeIdentity> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'cryptographicPublicKey', objects,
        saveLinks: saveLinks);
  }
}

extension NodeIdentityQueryWhereSort
    on QueryBuilder<NodeIdentity, NodeIdentity, QWhere> {
  QueryBuilder<NodeIdentity, NodeIdentity, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension NodeIdentityQueryWhere
    on QueryBuilder<NodeIdentity, NodeIdentity, QWhereClause> {
  QueryBuilder<NodeIdentity, NodeIdentity, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterWhereClause> idNotEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterWhereClause>
      cryptographicPublicKeyEqualTo(String cryptographicPublicKey) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'cryptographicPublicKey',
        value: [cryptographicPublicKey],
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterWhereClause>
      cryptographicPublicKeyNotEqualTo(String cryptographicPublicKey) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cryptographicPublicKey',
              lower: [],
              upper: [cryptographicPublicKey],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cryptographicPublicKey',
              lower: [cryptographicPublicKey],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cryptographicPublicKey',
              lower: [cryptographicPublicKey],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cryptographicPublicKey',
              lower: [],
              upper: [cryptographicPublicKey],
              includeUpper: false,
            ));
      }
    });
  }
}

extension NodeIdentityQueryFilter
    on QueryBuilder<NodeIdentity, NodeIdentity, QFilterCondition> {
  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      cryptographicPublicKeyEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cryptographicPublicKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      cryptographicPublicKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'cryptographicPublicKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      cryptographicPublicKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'cryptographicPublicKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      cryptographicPublicKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'cryptographicPublicKey',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      cryptographicPublicKeyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'cryptographicPublicKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      cryptographicPublicKeyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'cryptographicPublicKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      cryptographicPublicKeyContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'cryptographicPublicKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      cryptographicPublicKeyMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'cryptographicPublicKey',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      cryptographicPublicKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cryptographicPublicKey',
        value: '',
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      cryptographicPublicKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'cryptographicPublicKey',
        value: '',
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      hasValidKeyFormatEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hasValidKeyFormat',
        value: value,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      localAliasEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'localAlias',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      localAliasGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'localAlias',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      localAliasLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'localAlias',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      localAliasBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'localAlias',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      localAliasStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'localAlias',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      localAliasEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'localAlias',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      localAliasContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'localAlias',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      localAliasMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'localAlias',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      localAliasIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'localAlias',
        value: '',
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      localAliasIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'localAlias',
        value: '',
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      reliabilityScoreEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'reliabilityScore',
        value: value,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      reliabilityScoreGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'reliabilityScore',
        value: value,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      reliabilityScoreLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'reliabilityScore',
        value: value,
      ));
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterFilterCondition>
      reliabilityScoreBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'reliabilityScore',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension NodeIdentityQueryObject
    on QueryBuilder<NodeIdentity, NodeIdentity, QFilterCondition> {}

extension NodeIdentityQueryLinks
    on QueryBuilder<NodeIdentity, NodeIdentity, QFilterCondition> {}

extension NodeIdentityQuerySortBy
    on QueryBuilder<NodeIdentity, NodeIdentity, QSortBy> {
  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy>
      sortByCryptographicPublicKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cryptographicPublicKey', Sort.asc);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy>
      sortByCryptographicPublicKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cryptographicPublicKey', Sort.desc);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy>
      sortByHasValidKeyFormat() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasValidKeyFormat', Sort.asc);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy>
      sortByHasValidKeyFormatDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasValidKeyFormat', Sort.desc);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy> sortByLocalAlias() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localAlias', Sort.asc);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy>
      sortByLocalAliasDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localAlias', Sort.desc);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy>
      sortByReliabilityScore() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reliabilityScore', Sort.asc);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy>
      sortByReliabilityScoreDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reliabilityScore', Sort.desc);
    });
  }
}

extension NodeIdentityQuerySortThenBy
    on QueryBuilder<NodeIdentity, NodeIdentity, QSortThenBy> {
  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy>
      thenByCryptographicPublicKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cryptographicPublicKey', Sort.asc);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy>
      thenByCryptographicPublicKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cryptographicPublicKey', Sort.desc);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy>
      thenByHasValidKeyFormat() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasValidKeyFormat', Sort.asc);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy>
      thenByHasValidKeyFormatDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasValidKeyFormat', Sort.desc);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy> thenByLocalAlias() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localAlias', Sort.asc);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy>
      thenByLocalAliasDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localAlias', Sort.desc);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy>
      thenByReliabilityScore() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reliabilityScore', Sort.asc);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QAfterSortBy>
      thenByReliabilityScoreDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reliabilityScore', Sort.desc);
    });
  }
}

extension NodeIdentityQueryWhereDistinct
    on QueryBuilder<NodeIdentity, NodeIdentity, QDistinct> {
  QueryBuilder<NodeIdentity, NodeIdentity, QDistinct>
      distinctByCryptographicPublicKey({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cryptographicPublicKey',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QDistinct>
      distinctByHasValidKeyFormat() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hasValidKeyFormat');
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QDistinct> distinctByLocalAlias(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'localAlias', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<NodeIdentity, NodeIdentity, QDistinct>
      distinctByReliabilityScore() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'reliabilityScore');
    });
  }
}

extension NodeIdentityQueryProperty
    on QueryBuilder<NodeIdentity, NodeIdentity, QQueryProperty> {
  QueryBuilder<NodeIdentity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<NodeIdentity, String, QQueryOperations>
      cryptographicPublicKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cryptographicPublicKey');
    });
  }

  QueryBuilder<NodeIdentity, bool, QQueryOperations>
      hasValidKeyFormatProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hasValidKeyFormat');
    });
  }

  QueryBuilder<NodeIdentity, String, QQueryOperations> localAliasProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'localAlias');
    });
  }

  QueryBuilder<NodeIdentity, int, QQueryOperations> reliabilityScoreProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'reliabilityScore');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetResourceIntentCollection on Isar {
  IsarCollection<ResourceIntent> get resourceIntents => this.collection();
}

const ResourceIntentSchema = CollectionSchema(
  name: r'ResourceIntent',
  id: 8667911549906105658,
  properties: {
    r'allocationCategory': PropertySchema(
      id: 0,
      name: r'allocationCategory',
      type: IsarType.string,
      enumMap: _ResourceIntentallocationCategoryEnumValueMap,
    ),
    r'direction': PropertySchema(
      id: 1,
      name: r'direction',
      type: IsarType.string,
      enumMap: _ResourceIntentdirectionEnumValueMap,
    ),
    r'epochTimestamp': PropertySchema(
      id: 2,
      name: r'epochTimestamp',
      type: IsarType.long,
    ),
    r'intentUuid': PropertySchema(
      id: 3,
      name: r'intentUuid',
      type: IsarType.string,
    ),
    r'originNodeKey': PropertySchema(
      id: 4,
      name: r'originNodeKey',
      type: IsarType.string,
    ),
    r'rawTextPayload': PropertySchema(
      id: 5,
      name: r'rawTextPayload',
      type: IsarType.string,
    ),
    r'status': PropertySchema(
      id: 6,
      name: r'status',
      type: IsarType.string,
      enumMap: _ResourceIntentstatusEnumValueMap,
    ),
    r'structuralQuantity': PropertySchema(
      id: 7,
      name: r'structuralQuantity',
      type: IsarType.long,
    ),
    r'vectorData': PropertySchema(
      id: 8,
      name: r'vectorData',
      type: IsarType.floatList,
    )
  },
  estimateSize: _resourceIntentEstimateSize,
  serialize: _resourceIntentSerialize,
  deserialize: _resourceIntentDeserialize,
  deserializeProp: _resourceIntentDeserializeProp,
  idName: r'id',
  indexes: {
    r'intentUuid': IndexSchema(
      id: 4548438602546737674,
      name: r'intentUuid',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'intentUuid',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'originNodeKey': IndexSchema(
      id: -4390633975573404326,
      name: r'originNodeKey',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'originNodeKey',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'epochTimestamp': IndexSchema(
      id: -9151321446426978325,
      name: r'epochTimestamp',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'epochTimestamp',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _resourceIntentGetId,
  getLinks: _resourceIntentGetLinks,
  attach: _resourceIntentAttach,
  version: '3.1.0+1',
);

int _resourceIntentEstimateSize(
  ResourceIntent object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.allocationCategory.name.length * 3;
  bytesCount += 3 + object.direction.name.length * 3;
  bytesCount += 3 + object.intentUuid.length * 3;
  bytesCount += 3 + object.originNodeKey.length * 3;
  bytesCount += 3 + object.rawTextPayload.length * 3;
  bytesCount += 3 + object.status.name.length * 3;
  bytesCount += 3 + object.vectorData.length * 4;
  return bytesCount;
}

void _resourceIntentSerialize(
  ResourceIntent object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.allocationCategory.name);
  writer.writeString(offsets[1], object.direction.name);
  writer.writeLong(offsets[2], object.epochTimestamp);
  writer.writeString(offsets[3], object.intentUuid);
  writer.writeString(offsets[4], object.originNodeKey);
  writer.writeString(offsets[5], object.rawTextPayload);
  writer.writeString(offsets[6], object.status.name);
  writer.writeLong(offsets[7], object.structuralQuantity);
  writer.writeFloatList(offsets[8], object.vectorData);
}

ResourceIntent _resourceIntentDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = ResourceIntent(
    allocationCategory: _ResourceIntentallocationCategoryValueEnumMap[
            reader.readStringOrNull(offsets[0])] ??
        AllocationCategory.peerExchange,
    direction: _ResourceIntentdirectionValueEnumMap[
            reader.readStringOrNull(offsets[1])] ??
        IntentDirection.offer,
    epochTimestamp: reader.readLong(offsets[2]),
    intentUuid: reader.readString(offsets[3]),
    originNodeKey: reader.readString(offsets[4]),
    rawTextPayload: reader.readString(offsets[5]),
    structuralQuantity: reader.readLong(offsets[7]),
    vectorData: reader.readFloatList(offsets[8]) ?? [],
  );
  object.id = id;
  object.status =
      _ResourceIntentstatusValueEnumMap[reader.readStringOrNull(offsets[6])] ??
          IntentStatus.open;
  return object;
}

P _resourceIntentDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (_ResourceIntentallocationCategoryValueEnumMap[
              reader.readStringOrNull(offset)] ??
          AllocationCategory.peerExchange) as P;
    case 1:
      return (_ResourceIntentdirectionValueEnumMap[
              reader.readStringOrNull(offset)] ??
          IntentDirection.offer) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (_ResourceIntentstatusValueEnumMap[
              reader.readStringOrNull(offset)] ??
          IntentStatus.open) as P;
    case 7:
      return (reader.readLong(offset)) as P;
    case 8:
      return (reader.readFloatList(offset) ?? []) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

const _ResourceIntentallocationCategoryEnumValueMap = {
  r'peerExchange': r'peerExchange',
  r'computeAllocation': r'computeAllocation',
  r'energyTelemetry': r'energyTelemetry',
};
const _ResourceIntentallocationCategoryValueEnumMap = {
  r'peerExchange': AllocationCategory.peerExchange,
  r'computeAllocation': AllocationCategory.computeAllocation,
  r'energyTelemetry': AllocationCategory.energyTelemetry,
};
const _ResourceIntentdirectionEnumValueMap = {
  r'offer': r'offer',
  r'need': r'need',
};
const _ResourceIntentdirectionValueEnumMap = {
  r'offer': IntentDirection.offer,
  r'need': IntentDirection.need,
};
const _ResourceIntentstatusEnumValueMap = {
  r'open': r'open',
  r'lockedInLoop': r'lockedInLoop',
  r'satisfied': r'satisfied',
  r'withdrawn': r'withdrawn',
};
const _ResourceIntentstatusValueEnumMap = {
  r'open': IntentStatus.open,
  r'lockedInLoop': IntentStatus.lockedInLoop,
  r'satisfied': IntentStatus.satisfied,
  r'withdrawn': IntentStatus.withdrawn,
};

Id _resourceIntentGetId(ResourceIntent object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _resourceIntentGetLinks(ResourceIntent object) {
  return [];
}

void _resourceIntentAttach(
    IsarCollection<dynamic> col, Id id, ResourceIntent object) {
  object.id = id;
}

extension ResourceIntentByIndex on IsarCollection<ResourceIntent> {
  Future<ResourceIntent?> getByIntentUuid(String intentUuid) {
    return getByIndex(r'intentUuid', [intentUuid]);
  }

  ResourceIntent? getByIntentUuidSync(String intentUuid) {
    return getByIndexSync(r'intentUuid', [intentUuid]);
  }

  Future<bool> deleteByIntentUuid(String intentUuid) {
    return deleteByIndex(r'intentUuid', [intentUuid]);
  }

  bool deleteByIntentUuidSync(String intentUuid) {
    return deleteByIndexSync(r'intentUuid', [intentUuid]);
  }

  Future<List<ResourceIntent?>> getAllByIntentUuid(
      List<String> intentUuidValues) {
    final values = intentUuidValues.map((e) => [e]).toList();
    return getAllByIndex(r'intentUuid', values);
  }

  List<ResourceIntent?> getAllByIntentUuidSync(List<String> intentUuidValues) {
    final values = intentUuidValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'intentUuid', values);
  }

  Future<int> deleteAllByIntentUuid(List<String> intentUuidValues) {
    final values = intentUuidValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'intentUuid', values);
  }

  int deleteAllByIntentUuidSync(List<String> intentUuidValues) {
    final values = intentUuidValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'intentUuid', values);
  }

  Future<Id> putByIntentUuid(ResourceIntent object) {
    return putByIndex(r'intentUuid', object);
  }

  Id putByIntentUuidSync(ResourceIntent object, {bool saveLinks = true}) {
    return putByIndexSync(r'intentUuid', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByIntentUuid(List<ResourceIntent> objects) {
    return putAllByIndex(r'intentUuid', objects);
  }

  List<Id> putAllByIntentUuidSync(List<ResourceIntent> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'intentUuid', objects, saveLinks: saveLinks);
  }
}

extension ResourceIntentQueryWhereSort
    on QueryBuilder<ResourceIntent, ResourceIntent, QWhere> {
  QueryBuilder<ResourceIntent, ResourceIntent, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterWhere>
      anyEpochTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'epochTimestamp'),
      );
    });
  }
}

extension ResourceIntentQueryWhere
    on QueryBuilder<ResourceIntent, ResourceIntent, QWhereClause> {
  QueryBuilder<ResourceIntent, ResourceIntent, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterWhereClause> idNotEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterWhereClause>
      intentUuidEqualTo(String intentUuid) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'intentUuid',
        value: [intentUuid],
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterWhereClause>
      intentUuidNotEqualTo(String intentUuid) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'intentUuid',
              lower: [],
              upper: [intentUuid],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'intentUuid',
              lower: [intentUuid],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'intentUuid',
              lower: [intentUuid],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'intentUuid',
              lower: [],
              upper: [intentUuid],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterWhereClause>
      originNodeKeyEqualTo(String originNodeKey) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'originNodeKey',
        value: [originNodeKey],
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterWhereClause>
      originNodeKeyNotEqualTo(String originNodeKey) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'originNodeKey',
              lower: [],
              upper: [originNodeKey],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'originNodeKey',
              lower: [originNodeKey],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'originNodeKey',
              lower: [originNodeKey],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'originNodeKey',
              lower: [],
              upper: [originNodeKey],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterWhereClause>
      epochTimestampEqualTo(int epochTimestamp) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'epochTimestamp',
        value: [epochTimestamp],
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterWhereClause>
      epochTimestampNotEqualTo(int epochTimestamp) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'epochTimestamp',
              lower: [],
              upper: [epochTimestamp],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'epochTimestamp',
              lower: [epochTimestamp],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'epochTimestamp',
              lower: [epochTimestamp],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'epochTimestamp',
              lower: [],
              upper: [epochTimestamp],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterWhereClause>
      epochTimestampGreaterThan(
    int epochTimestamp, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'epochTimestamp',
        lower: [epochTimestamp],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterWhereClause>
      epochTimestampLessThan(
    int epochTimestamp, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'epochTimestamp',
        lower: [],
        upper: [epochTimestamp],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterWhereClause>
      epochTimestampBetween(
    int lowerEpochTimestamp,
    int upperEpochTimestamp, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'epochTimestamp',
        lower: [lowerEpochTimestamp],
        includeLower: includeLower,
        upper: [upperEpochTimestamp],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension ResourceIntentQueryFilter
    on QueryBuilder<ResourceIntent, ResourceIntent, QFilterCondition> {
  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      allocationCategoryEqualTo(
    AllocationCategory value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'allocationCategory',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      allocationCategoryGreaterThan(
    AllocationCategory value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'allocationCategory',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      allocationCategoryLessThan(
    AllocationCategory value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'allocationCategory',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      allocationCategoryBetween(
    AllocationCategory lower,
    AllocationCategory upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'allocationCategory',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      allocationCategoryStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'allocationCategory',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      allocationCategoryEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'allocationCategory',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      allocationCategoryContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'allocationCategory',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      allocationCategoryMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'allocationCategory',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      allocationCategoryIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'allocationCategory',
        value: '',
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      allocationCategoryIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'allocationCategory',
        value: '',
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      directionEqualTo(
    IntentDirection value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'direction',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      directionGreaterThan(
    IntentDirection value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'direction',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      directionLessThan(
    IntentDirection value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'direction',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      directionBetween(
    IntentDirection lower,
    IntentDirection upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'direction',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      directionStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'direction',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      directionEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'direction',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      directionContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'direction',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      directionMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'direction',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      directionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'direction',
        value: '',
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      directionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'direction',
        value: '',
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      epochTimestampEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'epochTimestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      epochTimestampGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'epochTimestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      epochTimestampLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'epochTimestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      epochTimestampBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'epochTimestamp',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      intentUuidEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'intentUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      intentUuidGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'intentUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      intentUuidLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'intentUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      intentUuidBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'intentUuid',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      intentUuidStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'intentUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      intentUuidEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'intentUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      intentUuidContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'intentUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      intentUuidMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'intentUuid',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      intentUuidIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'intentUuid',
        value: '',
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      intentUuidIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'intentUuid',
        value: '',
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      originNodeKeyEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'originNodeKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      originNodeKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'originNodeKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      originNodeKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'originNodeKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      originNodeKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'originNodeKey',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      originNodeKeyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'originNodeKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      originNodeKeyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'originNodeKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      originNodeKeyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'originNodeKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      originNodeKeyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'originNodeKey',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      originNodeKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'originNodeKey',
        value: '',
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      originNodeKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'originNodeKey',
        value: '',
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      rawTextPayloadEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'rawTextPayload',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      rawTextPayloadGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'rawTextPayload',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      rawTextPayloadLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'rawTextPayload',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      rawTextPayloadBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'rawTextPayload',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      rawTextPayloadStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'rawTextPayload',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      rawTextPayloadEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'rawTextPayload',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      rawTextPayloadContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'rawTextPayload',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      rawTextPayloadMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'rawTextPayload',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      rawTextPayloadIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'rawTextPayload',
        value: '',
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      rawTextPayloadIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'rawTextPayload',
        value: '',
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      statusEqualTo(
    IntentStatus value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      statusGreaterThan(
    IntentStatus value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      statusLessThan(
    IntentStatus value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      statusBetween(
    IntentStatus lower,
    IntentStatus upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'status',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      statusStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      statusEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      statusContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      statusMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'status',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      statusIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'status',
        value: '',
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      statusIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'status',
        value: '',
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      structuralQuantityEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'structuralQuantity',
        value: value,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      structuralQuantityGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'structuralQuantity',
        value: value,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      structuralQuantityLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'structuralQuantity',
        value: value,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      structuralQuantityBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'structuralQuantity',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      vectorDataElementEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'vectorData',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      vectorDataElementGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'vectorData',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      vectorDataElementLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'vectorData',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      vectorDataElementBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'vectorData',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      vectorDataLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'vectorData',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      vectorDataIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'vectorData',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      vectorDataIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'vectorData',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      vectorDataLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'vectorData',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      vectorDataLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'vectorData',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterFilterCondition>
      vectorDataLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'vectorData',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }
}

extension ResourceIntentQueryObject
    on QueryBuilder<ResourceIntent, ResourceIntent, QFilterCondition> {}

extension ResourceIntentQueryLinks
    on QueryBuilder<ResourceIntent, ResourceIntent, QFilterCondition> {}

extension ResourceIntentQuerySortBy
    on QueryBuilder<ResourceIntent, ResourceIntent, QSortBy> {
  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      sortByAllocationCategory() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'allocationCategory', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      sortByAllocationCategoryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'allocationCategory', Sort.desc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy> sortByDirection() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'direction', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      sortByDirectionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'direction', Sort.desc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      sortByEpochTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'epochTimestamp', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      sortByEpochTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'epochTimestamp', Sort.desc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      sortByIntentUuid() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'intentUuid', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      sortByIntentUuidDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'intentUuid', Sort.desc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      sortByOriginNodeKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originNodeKey', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      sortByOriginNodeKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originNodeKey', Sort.desc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      sortByRawTextPayload() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rawTextPayload', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      sortByRawTextPayloadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rawTextPayload', Sort.desc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy> sortByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      sortByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      sortByStructuralQuantity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'structuralQuantity', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      sortByStructuralQuantityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'structuralQuantity', Sort.desc);
    });
  }
}

extension ResourceIntentQuerySortThenBy
    on QueryBuilder<ResourceIntent, ResourceIntent, QSortThenBy> {
  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      thenByAllocationCategory() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'allocationCategory', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      thenByAllocationCategoryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'allocationCategory', Sort.desc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy> thenByDirection() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'direction', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      thenByDirectionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'direction', Sort.desc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      thenByEpochTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'epochTimestamp', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      thenByEpochTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'epochTimestamp', Sort.desc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      thenByIntentUuid() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'intentUuid', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      thenByIntentUuidDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'intentUuid', Sort.desc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      thenByOriginNodeKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originNodeKey', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      thenByOriginNodeKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originNodeKey', Sort.desc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      thenByRawTextPayload() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rawTextPayload', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      thenByRawTextPayloadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rawTextPayload', Sort.desc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy> thenByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      thenByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      thenByStructuralQuantity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'structuralQuantity', Sort.asc);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QAfterSortBy>
      thenByStructuralQuantityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'structuralQuantity', Sort.desc);
    });
  }
}

extension ResourceIntentQueryWhereDistinct
    on QueryBuilder<ResourceIntent, ResourceIntent, QDistinct> {
  QueryBuilder<ResourceIntent, ResourceIntent, QDistinct>
      distinctByAllocationCategory({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'allocationCategory',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QDistinct> distinctByDirection(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'direction', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QDistinct>
      distinctByEpochTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'epochTimestamp');
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QDistinct> distinctByIntentUuid(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'intentUuid', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QDistinct>
      distinctByOriginNodeKey({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'originNodeKey',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QDistinct>
      distinctByRawTextPayload({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'rawTextPayload',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QDistinct> distinctByStatus(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'status', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QDistinct>
      distinctByStructuralQuantity() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'structuralQuantity');
    });
  }

  QueryBuilder<ResourceIntent, ResourceIntent, QDistinct>
      distinctByVectorData() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'vectorData');
    });
  }
}

extension ResourceIntentQueryProperty
    on QueryBuilder<ResourceIntent, ResourceIntent, QQueryProperty> {
  QueryBuilder<ResourceIntent, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<ResourceIntent, AllocationCategory, QQueryOperations>
      allocationCategoryProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'allocationCategory');
    });
  }

  QueryBuilder<ResourceIntent, IntentDirection, QQueryOperations>
      directionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'direction');
    });
  }

  QueryBuilder<ResourceIntent, int, QQueryOperations> epochTimestampProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'epochTimestamp');
    });
  }

  QueryBuilder<ResourceIntent, String, QQueryOperations> intentUuidProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'intentUuid');
    });
  }

  QueryBuilder<ResourceIntent, String, QQueryOperations>
      originNodeKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'originNodeKey');
    });
  }

  QueryBuilder<ResourceIntent, String, QQueryOperations>
      rawTextPayloadProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'rawTextPayload');
    });
  }

  QueryBuilder<ResourceIntent, IntentStatus, QQueryOperations>
      statusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'status');
    });
  }

  QueryBuilder<ResourceIntent, int, QQueryOperations>
      structuralQuantityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'structuralQuantity');
    });
  }

  QueryBuilder<ResourceIntent, List<double>, QQueryOperations>
      vectorDataProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'vectorData');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetCrdtStateLogCollection on Isar {
  IsarCollection<CrdtStateLog> get crdtStateLogs => this.collection();
}

const CrdtStateLogSchema = CollectionSchema(
  name: r'CrdtStateLog',
  id: 6606120135497158350,
  properties: {
    r'authoritySignature': PropertySchema(
      id: 0,
      name: r'authoritySignature',
      type: IsarType.string,
    ),
    r'lamportLogicalClock': PropertySchema(
      id: 1,
      name: r'lamportLogicalClock',
      type: IsarType.long,
    ),
    r'operationPayloadJson': PropertySchema(
      id: 2,
      name: r'operationPayloadJson',
      type: IsarType.string,
    ),
    r'targetIntentUuid': PropertySchema(
      id: 3,
      name: r'targetIntentUuid',
      type: IsarType.string,
    ),
    r'transactionUuid': PropertySchema(
      id: 4,
      name: r'transactionUuid',
      type: IsarType.string,
    )
  },
  estimateSize: _crdtStateLogEstimateSize,
  serialize: _crdtStateLogSerialize,
  deserialize: _crdtStateLogDeserialize,
  deserializeProp: _crdtStateLogDeserializeProp,
  idName: r'id',
  indexes: {
    r'transactionUuid': IndexSchema(
      id: -5468758077976123440,
      name: r'transactionUuid',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'transactionUuid',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'targetIntentUuid_lamportLogicalClock': IndexSchema(
      id: -5228129618252962927,
      name: r'targetIntentUuid_lamportLogicalClock',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'targetIntentUuid',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'lamportLogicalClock',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _crdtStateLogGetId,
  getLinks: _crdtStateLogGetLinks,
  attach: _crdtStateLogAttach,
  version: '3.1.0+1',
);

int _crdtStateLogEstimateSize(
  CrdtStateLog object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.authoritySignature.length * 3;
  bytesCount += 3 + object.operationPayloadJson.length * 3;
  bytesCount += 3 + object.targetIntentUuid.length * 3;
  bytesCount += 3 + object.transactionUuid.length * 3;
  return bytesCount;
}

void _crdtStateLogSerialize(
  CrdtStateLog object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.authoritySignature);
  writer.writeLong(offsets[1], object.lamportLogicalClock);
  writer.writeString(offsets[2], object.operationPayloadJson);
  writer.writeString(offsets[3], object.targetIntentUuid);
  writer.writeString(offsets[4], object.transactionUuid);
}

CrdtStateLog _crdtStateLogDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = CrdtStateLog(
    authoritySignature: reader.readString(offsets[0]),
    lamportLogicalClock: reader.readLong(offsets[1]),
    operationPayloadJson: reader.readString(offsets[2]),
    targetIntentUuid: reader.readString(offsets[3]),
    transactionUuid: reader.readString(offsets[4]),
  );
  object.id = id;
  return object;
}

P _crdtStateLogDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _crdtStateLogGetId(CrdtStateLog object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _crdtStateLogGetLinks(CrdtStateLog object) {
  return [];
}

void _crdtStateLogAttach(
    IsarCollection<dynamic> col, Id id, CrdtStateLog object) {
  object.id = id;
}

extension CrdtStateLogByIndex on IsarCollection<CrdtStateLog> {
  Future<CrdtStateLog?> getByTransactionUuid(String transactionUuid) {
    return getByIndex(r'transactionUuid', [transactionUuid]);
  }

  CrdtStateLog? getByTransactionUuidSync(String transactionUuid) {
    return getByIndexSync(r'transactionUuid', [transactionUuid]);
  }

  Future<bool> deleteByTransactionUuid(String transactionUuid) {
    return deleteByIndex(r'transactionUuid', [transactionUuid]);
  }

  bool deleteByTransactionUuidSync(String transactionUuid) {
    return deleteByIndexSync(r'transactionUuid', [transactionUuid]);
  }

  Future<List<CrdtStateLog?>> getAllByTransactionUuid(
      List<String> transactionUuidValues) {
    final values = transactionUuidValues.map((e) => [e]).toList();
    return getAllByIndex(r'transactionUuid', values);
  }

  List<CrdtStateLog?> getAllByTransactionUuidSync(
      List<String> transactionUuidValues) {
    final values = transactionUuidValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'transactionUuid', values);
  }

  Future<int> deleteAllByTransactionUuid(List<String> transactionUuidValues) {
    final values = transactionUuidValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'transactionUuid', values);
  }

  int deleteAllByTransactionUuidSync(List<String> transactionUuidValues) {
    final values = transactionUuidValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'transactionUuid', values);
  }

  Future<Id> putByTransactionUuid(CrdtStateLog object) {
    return putByIndex(r'transactionUuid', object);
  }

  Id putByTransactionUuidSync(CrdtStateLog object, {bool saveLinks = true}) {
    return putByIndexSync(r'transactionUuid', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByTransactionUuid(List<CrdtStateLog> objects) {
    return putAllByIndex(r'transactionUuid', objects);
  }

  List<Id> putAllByTransactionUuidSync(List<CrdtStateLog> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'transactionUuid', objects, saveLinks: saveLinks);
  }
}

extension CrdtStateLogQueryWhereSort
    on QueryBuilder<CrdtStateLog, CrdtStateLog, QWhere> {
  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension CrdtStateLogQueryWhere
    on QueryBuilder<CrdtStateLog, CrdtStateLog, QWhereClause> {
  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterWhereClause> idNotEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterWhereClause>
      transactionUuidEqualTo(String transactionUuid) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'transactionUuid',
        value: [transactionUuid],
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterWhereClause>
      transactionUuidNotEqualTo(String transactionUuid) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'transactionUuid',
              lower: [],
              upper: [transactionUuid],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'transactionUuid',
              lower: [transactionUuid],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'transactionUuid',
              lower: [transactionUuid],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'transactionUuid',
              lower: [],
              upper: [transactionUuid],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterWhereClause>
      targetIntentUuidEqualToAnyLamportLogicalClock(String targetIntentUuid) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'targetIntentUuid_lamportLogicalClock',
        value: [targetIntentUuid],
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterWhereClause>
      targetIntentUuidNotEqualToAnyLamportLogicalClock(
          String targetIntentUuid) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'targetIntentUuid_lamportLogicalClock',
              lower: [],
              upper: [targetIntentUuid],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'targetIntentUuid_lamportLogicalClock',
              lower: [targetIntentUuid],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'targetIntentUuid_lamportLogicalClock',
              lower: [targetIntentUuid],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'targetIntentUuid_lamportLogicalClock',
              lower: [],
              upper: [targetIntentUuid],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterWhereClause>
      targetIntentUuidLamportLogicalClockEqualTo(
          String targetIntentUuid, int lamportLogicalClock) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'targetIntentUuid_lamportLogicalClock',
        value: [targetIntentUuid, lamportLogicalClock],
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterWhereClause>
      targetIntentUuidEqualToLamportLogicalClockNotEqualTo(
          String targetIntentUuid, int lamportLogicalClock) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'targetIntentUuid_lamportLogicalClock',
              lower: [targetIntentUuid],
              upper: [targetIntentUuid, lamportLogicalClock],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'targetIntentUuid_lamportLogicalClock',
              lower: [targetIntentUuid, lamportLogicalClock],
              includeLower: false,
              upper: [targetIntentUuid],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'targetIntentUuid_lamportLogicalClock',
              lower: [targetIntentUuid, lamportLogicalClock],
              includeLower: false,
              upper: [targetIntentUuid],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'targetIntentUuid_lamportLogicalClock',
              lower: [targetIntentUuid],
              upper: [targetIntentUuid, lamportLogicalClock],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterWhereClause>
      targetIntentUuidEqualToLamportLogicalClockGreaterThan(
    String targetIntentUuid,
    int lamportLogicalClock, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'targetIntentUuid_lamportLogicalClock',
        lower: [targetIntentUuid, lamportLogicalClock],
        includeLower: include,
        upper: [targetIntentUuid],
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterWhereClause>
      targetIntentUuidEqualToLamportLogicalClockLessThan(
    String targetIntentUuid,
    int lamportLogicalClock, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'targetIntentUuid_lamportLogicalClock',
        lower: [targetIntentUuid],
        upper: [targetIntentUuid, lamportLogicalClock],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterWhereClause>
      targetIntentUuidEqualToLamportLogicalClockBetween(
    String targetIntentUuid,
    int lowerLamportLogicalClock,
    int upperLamportLogicalClock, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'targetIntentUuid_lamportLogicalClock',
        lower: [targetIntentUuid, lowerLamportLogicalClock],
        includeLower: includeLower,
        upper: [targetIntentUuid, upperLamportLogicalClock],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension CrdtStateLogQueryFilter
    on QueryBuilder<CrdtStateLog, CrdtStateLog, QFilterCondition> {
  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      authoritySignatureEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'authoritySignature',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      authoritySignatureGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'authoritySignature',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      authoritySignatureLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'authoritySignature',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      authoritySignatureBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'authoritySignature',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      authoritySignatureStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'authoritySignature',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      authoritySignatureEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'authoritySignature',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      authoritySignatureContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'authoritySignature',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      authoritySignatureMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'authoritySignature',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      authoritySignatureIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'authoritySignature',
        value: '',
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      authoritySignatureIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'authoritySignature',
        value: '',
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      lamportLogicalClockEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lamportLogicalClock',
        value: value,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      lamportLogicalClockGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lamportLogicalClock',
        value: value,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      lamportLogicalClockLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lamportLogicalClock',
        value: value,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      lamportLogicalClockBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lamportLogicalClock',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      operationPayloadJsonEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'operationPayloadJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      operationPayloadJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'operationPayloadJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      operationPayloadJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'operationPayloadJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      operationPayloadJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'operationPayloadJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      operationPayloadJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'operationPayloadJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      operationPayloadJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'operationPayloadJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      operationPayloadJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'operationPayloadJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      operationPayloadJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'operationPayloadJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      operationPayloadJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'operationPayloadJson',
        value: '',
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      operationPayloadJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'operationPayloadJson',
        value: '',
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      targetIntentUuidEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'targetIntentUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      targetIntentUuidGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'targetIntentUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      targetIntentUuidLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'targetIntentUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      targetIntentUuidBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'targetIntentUuid',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      targetIntentUuidStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'targetIntentUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      targetIntentUuidEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'targetIntentUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      targetIntentUuidContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'targetIntentUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      targetIntentUuidMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'targetIntentUuid',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      targetIntentUuidIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'targetIntentUuid',
        value: '',
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      targetIntentUuidIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'targetIntentUuid',
        value: '',
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      transactionUuidEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'transactionUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      transactionUuidGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'transactionUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      transactionUuidLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'transactionUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      transactionUuidBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'transactionUuid',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      transactionUuidStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'transactionUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      transactionUuidEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'transactionUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      transactionUuidContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'transactionUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      transactionUuidMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'transactionUuid',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      transactionUuidIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'transactionUuid',
        value: '',
      ));
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterFilterCondition>
      transactionUuidIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'transactionUuid',
        value: '',
      ));
    });
  }
}

extension CrdtStateLogQueryObject
    on QueryBuilder<CrdtStateLog, CrdtStateLog, QFilterCondition> {}

extension CrdtStateLogQueryLinks
    on QueryBuilder<CrdtStateLog, CrdtStateLog, QFilterCondition> {}

extension CrdtStateLogQuerySortBy
    on QueryBuilder<CrdtStateLog, CrdtStateLog, QSortBy> {
  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      sortByAuthoritySignature() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'authoritySignature', Sort.asc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      sortByAuthoritySignatureDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'authoritySignature', Sort.desc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      sortByLamportLogicalClock() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lamportLogicalClock', Sort.asc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      sortByLamportLogicalClockDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lamportLogicalClock', Sort.desc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      sortByOperationPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'operationPayloadJson', Sort.asc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      sortByOperationPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'operationPayloadJson', Sort.desc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      sortByTargetIntentUuid() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetIntentUuid', Sort.asc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      sortByTargetIntentUuidDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetIntentUuid', Sort.desc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      sortByTransactionUuid() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transactionUuid', Sort.asc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      sortByTransactionUuidDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transactionUuid', Sort.desc);
    });
  }
}

extension CrdtStateLogQuerySortThenBy
    on QueryBuilder<CrdtStateLog, CrdtStateLog, QSortThenBy> {
  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      thenByAuthoritySignature() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'authoritySignature', Sort.asc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      thenByAuthoritySignatureDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'authoritySignature', Sort.desc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      thenByLamportLogicalClock() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lamportLogicalClock', Sort.asc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      thenByLamportLogicalClockDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lamportLogicalClock', Sort.desc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      thenByOperationPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'operationPayloadJson', Sort.asc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      thenByOperationPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'operationPayloadJson', Sort.desc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      thenByTargetIntentUuid() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetIntentUuid', Sort.asc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      thenByTargetIntentUuidDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetIntentUuid', Sort.desc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      thenByTransactionUuid() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transactionUuid', Sort.asc);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QAfterSortBy>
      thenByTransactionUuidDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transactionUuid', Sort.desc);
    });
  }
}

extension CrdtStateLogQueryWhereDistinct
    on QueryBuilder<CrdtStateLog, CrdtStateLog, QDistinct> {
  QueryBuilder<CrdtStateLog, CrdtStateLog, QDistinct>
      distinctByAuthoritySignature({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'authoritySignature',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QDistinct>
      distinctByLamportLogicalClock() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lamportLogicalClock');
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QDistinct>
      distinctByOperationPayloadJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'operationPayloadJson',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QDistinct>
      distinctByTargetIntentUuid({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'targetIntentUuid',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CrdtStateLog, CrdtStateLog, QDistinct> distinctByTransactionUuid(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'transactionUuid',
          caseSensitive: caseSensitive);
    });
  }
}

extension CrdtStateLogQueryProperty
    on QueryBuilder<CrdtStateLog, CrdtStateLog, QQueryProperty> {
  QueryBuilder<CrdtStateLog, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<CrdtStateLog, String, QQueryOperations>
      authoritySignatureProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'authoritySignature');
    });
  }

  QueryBuilder<CrdtStateLog, int, QQueryOperations>
      lamportLogicalClockProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lamportLogicalClock');
    });
  }

  QueryBuilder<CrdtStateLog, String, QQueryOperations>
      operationPayloadJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'operationPayloadJson');
    });
  }

  QueryBuilder<CrdtStateLog, String, QQueryOperations>
      targetIntentUuidProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'targetIntentUuid');
    });
  }

  QueryBuilder<CrdtStateLog, String, QQueryOperations>
      transactionUuidProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'transactionUuid');
    });
  }
}
